import SwiftUI
import UniformTypeIdentifiers

/// First-run "set up from another device" flow, entered from the restore bottom sheet
/// with a chosen method: obtain the EXISTING vault's key — by QR pairing (a trusted
/// device scans this device's code and hands the key off end-to-end encrypted) or by
/// entering / importing the Emergency-Kit recovery key against the synced recovery
/// envelope — then set a local master password and pull the vault. A header back button
/// abandons the flow; no first-run seeding happens here (see `VaultSession.joinVault`).
struct JoinVaultFlow: View {
    enum Method { case qr, recovery }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let method: Method
    let onCancel: () -> Void

    private enum Step: Equatable { case entry, password, biometric }

    @State private var step: Step = .entry
    /// The received Vault Key, held only between hand-off and `joinVault`. Kept as
    /// `SecureBytes` (mlocked, zeroed on deinit) — a raw array in `@State` would defeat
    /// zeroization via copy-on-write and could linger after an abandoned flow.
    @State private var receivedKey: SecureBytes?
    /// Set when the key came from the recovery path, so the same Emergency Kit
    /// keeps working on this device (re-wrapped locally).
    @State private var usedRecoveryKey: String?

    var body: some View {
        // Native nav bar so the back control is the standard iOS chevron (a Liquid
        // Glass pill on iOS 26), not a hand-rolled icon.
        NavigationStack {
            content
                // Canvas convention: screens WITHOUT form fields / grouped cards
                // are plain white (QR pairing, biometric); form screens use the
                // grouped gray so white fields stay visible.
                .background(canvasColor.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if step != .biometric {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: back) { Image(systemName: "chevron.backward") }
                                .accessibilityLabel(Text("Back"))
                        }
                    }
                }
                .tint(Color.primary)
        }
        .animation(.vault(.smooth(duration: 0.35), reduceMotion: reduceMotion), value: step)
        // Backing out of the password step abandons the hand-off — drop the key
        // (SecureBytes deinit zeroes it) instead of leaving it parked in state.
        .onChange(of: step) { _, newStep in
            if newStep == .entry { clearReceivedKey() }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .entry:
            switch method {
            case .qr:
                JoinByQRView(onKey: { adoptKey($0, recoveryKey: nil) })
            case .recovery:
                JoinByRecoveryView(onKey: { key, recoveryKey in adoptKey(key, recoveryKey: recoveryKey) })
            }
        case .password:
            // Join-specific copy: the vault EXISTS and was just received — without
            // this context the reused creation screen reads like "pairing failed,
            // a brand-new vault is being made".
            CreateMasterPasswordView(
                onSubmit: completeJoin,
                title: "Vault received. Protect this device",
                subtitle: "Pairing succeeded. Now create a master password to unlock Loox on this device. It can match your other device or be different, and it never syncs.")
        case .biometric:
            EnableBiometricView(onEnable: enableBiometricAndFinish) { finish() }
        }
    }

    private var canvasColor: Color {
        switch step {
        case .entry where method == .qr, .biometric:
            return Color(rgb: env.theme.active.background)
        default:
            return Color(rgb: env.theme.active.groupedBackground)
        }
    }

    private func back() {
        switch step {
        case .entry: onCancel()
        case .password: step = .entry
        case .biometric: break
        }
    }

    /// Move the received key straight into zeroing storage and advance.
    private func adoptKey(_ key: [UInt8], recoveryKey: String?) {
        var bytes = key
        receivedKey = SecureBytes(bytes)
        secureZero(&bytes)
        usedRecoveryKey = recoveryKey
        step = .password
    }

    private func clearReceivedKey() {
        receivedKey = nil
        usedRecoveryKey = nil
    }

    /// Wrap the received key under the chosen local password, enable sync, and pull.
    private func completeJoin(_ password: String) async -> String? {
        guard let key = receivedKey else { return appString("Pairing failed. Try again with a fresh QR code.") }
        do {
            // `.bytes` yields a fresh, uniquely-referenced copy → zeroing it works.
            var bytes = key.bytes
            defer { secureZero(&bytes) }
            try await env.session.joinVault(vaultKey: bytes, masterPassword: password,
                                            recoveryKey: usedRecoveryKey)
            clearReceivedKey()
            // Joining is an explicit iCloud action — turn sync on and start pulling
            // right away (the vault downloads while the user finishes the last step).
            env.settings.iCloudSyncEnabled = true
            env.syncNow()
            if BiometricAuth.isAvailable {
                step = .biometric
            } else {
                finish()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func enableBiometricAndFinish() {
        Task {
            try? await env.session.enableBiometricUnlock()
            finish()
        }
    }

    /// Leave onboarding — the unlocked app takes over (content arrives via sync).
    private func finish() {
        env.settings.onboardingCompleted = true
    }
}

// MARK: - Restore method chooser (bottom sheet)

/// Bottom-sheet chooser presented when the user taps "Restore" on the welcome screen:
/// pick QR pairing or the Emergency-Kit recovery key. The parent flips onboarding to
/// the chosen method; the close control just dismisses.
struct RestoreMethodSheet: View {
    let onQR: () -> Void
    let onRecovery: () -> Void
    /// "Want to start fresh?" — leave restore and go straight into vault
    /// creation (same destination as the welcome Get started).
    let onStartFresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        // Apple-Account-style sheet: white page, the system close control, the
        // brand swirl centred, left-aligned title + description, a link that
        // bails out to a fresh start, and gray option boxes with tinted icons.
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    LooxSwirlAnimationView()
                        .frame(width: 130, height: 130)
                        .frame(maxWidth: .infinity)
                        // The toolbar X already anchors the top — keep the swirl
                        // close to it and give the air to the gap below instead.
                        .padding(.top, Space.s4)

                    Text("Restore data")
                        .vaultType(.screenTitle)
                        .padding(.top, Space.s9)
                    Text("Move your vault from another device, or reopen it with your Emergency Kit.")
                        .vaultType(.body).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Space.s2)

                    Button { onStartFresh() } label: {
                        Text("Want to start fresh?")
                            .vaultType(.body)
                            .themedForeground(.accentText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Space.s4)

                    VStack(spacing: Space.s3) {
                        restoreOptionBox(icon: "PairDeviceDuotone",
                                         title: "Pair with an old device",
                                         detail: "Scan a QR code between two iPhones to move the whole vault.",
                                         action: onQR)
                        restoreOptionBox(icon: "RecoveryKitDuotone",
                                         title: "Use Recovery Key",
                                         detail: "Enter the key printed in the Emergency Kit (PDF) you saved.",
                                         action: onRecovery)
                    }
                    .padding(.top, Space.s6)
                }
                .padding(.horizontal, Space.s6)
                .padding(.bottom, Space.s7)
            }
            .toolbar {
                // The system toolbar close (glass pill on iOS 26), tinted by the
                // app's neutral default.
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(Text("Close"))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Color.primary)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// One gray option box: bare tinted icon, bold title + gray detail, chevron.
    private func restoreOptionBox(icon: String, title: LocalizedStringResource,
                                  detail: LocalizedStringResource,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Icon top-aligned with the title line (not row-centred).
            HStack(alignment: .top, spacing: Space.s4) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(title.inAppLocalized)
                        .vaultType(.headline).themedForeground(.primary)
                    Text(detail.inAppLocalized)
                        .vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                PolarisIcon(Icons.chevronRight, size: Metric.iconInline)
                    .themedForeground(.iconSecondary)
                    .frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(Space.s5)
            .background(Color(rgb: env.theme.active.secondaryBackground),
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


// MARK: - QR pairing (new-device side)

private struct JoinByQRView: View {
    let onKey: ([UInt8]) -> Void
    @Environment(AppEnvironment.self) private var env

    @State private var session = VaultKeyPairing.makeSession()
    @State private var errorMessage: String?
    @State private var waitTask: Task<Void, Never>?

    var body: some View {
        OnboardingScrollingStep {
            VStack(spacing: 0) {
                Spacer().frame(height: Space.s3)
                // Loading loop while waiting; on timeout the animation restarts once
                // and settles (no loop). Start Over (clearing the error) resumes it.
                LooxSwirlAnimationView(mode: errorMessage == nil ? .loop : .reveal)
                    .frame(width: 140, height: 140)

                // Extra clearance below the swirl: its dispersal spills past the
                // frame, so the title must sit clear of the fading dots.
                OnboardingStepHeader("Pair with QR Code", style: .compact)
                    .padding(.top, Space.s7)

                guideBreadcrumb
                    .padding(.top, Space.s3)
                    .padding(.horizontal, Space.s6)

                QRCodeView(payload: session.qrPayload)
                    .frame(maxWidth: 260)
                    .padding(.top, Space.s5)

                Group {
                    if let errorMessage {
                        errorCard(errorMessage)
                    } else {
                        Text("Waiting for your other device…")
                            .vaultType(.subhead).themedForeground(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s5)

                Spacer(minLength: Space.s6)
                if errorMessage != nil {
                    Button {
                        // A fresh session (new ephemeral key + pairing id) — the old QR is dead.
                        session = VaultKeyPairing.makeSession()
                        errorMessage = nil
                        startWaiting()
                    } label: {
                        Text("Start over").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, Space.s6)
                    .padding(.bottom, Space.s6)
                }
            }
        }
        .onAppear(perform: startWaiting)
        .onDisappear { waitTask?.cancel() }
    }

    /// The full guide sentence with the settings path highlighted INLINE: the
    /// bold segments (markdown) are re-tinted to the accent so "Settings →
    /// iCloud Sync → Pair New Device" pops out of the flowing prose.
    private var guideBreadcrumb: some View {
        Text(guideText)
            .vaultType(.subhead).themedForeground(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var guideText: AttributedString {
        var text = (try? AttributedString(
            markdown: appString("On your other device, open **Settings** → **iCloud Sync** → **Pair New Device**, then scan this code.")))
            ?? AttributedString(appString("On your other device, open Settings → iCloud Sync → Pair New Device, then scan this code."))
        for run in text.runs
        where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].foregroundColor = Color(rgb: env.theme.active.accentText)
            text[run.range].font = VaultType.subhead.font.weight(.semibold)
        }
        return text
    }

    /// Refined failure card: soft red surface, a circled X, and the message —
    /// replaces the bare red error line.
    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(rgb: env.theme.active.destructive))
            Text(verbatim: message)
                .vaultType(.footnote).themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.s4)
        .background(Color(rgb: env.theme.active.destructiveSoft),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func startWaiting() {
        waitTask?.cancel()
        let escrow = VaultKeyEscrowService()
        let current = session
        waitTask = Task {
            do {
                let sealed = try await escrow.waitForPairingHandoff(pairingId: current.pairingId)
                let key = try VaultKeyPairing.open(sealed, session: current)
                guard !Task.isCancelled else { return }
                onKey(key)
            } catch is CancellationError {
                // View dismissed — nothing to report.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Recovery key (Emergency-Kit side)

private struct JoinByRecoveryView: View {
    let onKey: ([UInt8], _ recoveryKey: String) -> Void
    @Environment(AppEnvironment.self) private var env

    @State private var recoveryKey = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showScanner = false
    @State private var showPDFImporter = false

    var body: some View {
        OnboardingScrollingStep {
            VStack(spacing: 0) {
                Spacer().frame(height: Space.s3)
                LooxSwirlAnimationView()
                    .frame(width: 150, height: 150)
                OnboardingStepHeader(
                    "Use Recovery Key",
                    subtitle: "Import your saved Emergency Kit PDF, scan its Setup Code, or type the recovery key. Your vault will download from iCloud.",
                    style: .compact)

                VStack(spacing: Space.s4) {
                    recoveryField
                    #if os(iOS)
                    orSeparator
                    pdfDropBox
                    #endif
                }
                .padding(.horizontal, Space.s6)
                .padding(.top, Space.s6)

                if let errorMessage {
                    Text(errorMessage)
                        .vaultType(.footnote)
                        .foregroundStyle(VaultColors.strengthWeak)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.s6)
                        .padding(.top, Space.s4)
                }

                Spacer(minLength: Space.s6)
                Button(action: submit) {
                    Group {
                        if busy { ProgressView() } else { Text("Continue") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                .controlSize(.large)
                .disabled(recoveryKey.isEmpty || busy)
                .padding(.horizontal, Space.s6)
                .padding(.bottom, Space.s6)
            }
        }
        // Dismiss the keyboard on scroll or a tap outside the field (buttons/field
        // keep their own handling — children win over this gesture).
        .scrollDismissesKeyboard(.immediately)
        .onTapGesture { dismissKeyboard() }
        #if os(iOS)
        .sheet(isPresented: $showScanner) {
            RecoveryScannerSheet { scanned in
                recoveryKey = scanned
                showScanner = false
            } onCancel: { showScanner = false }
        }
        #endif
    }

    private var recoveryField: some View {
        HStack(spacing: Space.s2) {
            PolarisIcon(Icons.key, size: Metric.iconInline)
                .foregroundStyle(Color(rgb: env.theme.active.accent))
                .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                .background(Color(rgb: env.theme.active.accentSoft),
                            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            TextField("Recovery key", text: $recoveryKey, axis: .vertical)
                .font(recoveryKey.isEmpty ? VaultType.body.font : .vaultCode())
                .platformAutocapitalization(.characters)
                .autocorrectionDisabled()
                .frame(maxWidth: .infinity, alignment: .leading)
            #if os(iOS)
            Button { showScanner = true } label: {
                PolarisIcon(Icons.scanCode, size: Metric.iconInline)
                    .foregroundStyle(Color(rgb: env.theme.active.accent))
                    .frame(width: Metric.hitMin, height: Metric.hitMin, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityLabel(Text("Scan Setup Code"))
            #endif
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(Color(rgb: env.theme.active.elevatedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .elevation(.level2)
    }

    #if os(iOS)
    /// "or" rule between the typed key and the PDF drop zone.
    private var orSeparator: some View {
        HStack(spacing: Space.s3) {
            dash
            Text("or").vaultType(.footnote).themedForeground(.tertiary)
            dash
        }
    }

    private var dash: some View {
        DashLine()
            .stroke(Color(rgb: env.theme.active.separator), lineWidth: 1)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    /// Dashed "drop zone" that opens the file picker on tap (drag-and-drop look;
    /// tap to choose the saved Emergency Kit PDF). The `.fileImporter` lives HERE,
    /// not next to the scanner `.sheet` above — two presentation modifiers on the
    /// same view make SwiftUI drop one, which is why the picker never opened.
    private var pdfDropBox: some View {
        Button { showPDFImporter = true } label: {
            VStack(spacing: Space.s2) {
                if busy {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 26))
                        .foregroundStyle(Color(rgb: env.theme.active.accent))
                    Text("Import from PDF")
                        .vaultType(.callout).fontWeight(.semibold).themedForeground(.primary)
                    Text("Tap to choose your saved Emergency Kit PDF")
                        .vaultType(.footnote).themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s6)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color(rgb: env.theme.active.accentSoft).opacity(0.3)))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Color(rgb: env.theme.active.accent).opacity(0.5),
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
        // Accept any file (not only `.pdf`) so nothing greys out in providers that
        // report an Emergency Kit PDF under a generic type; we validate it really is
        // a readable PDF with a Setup Code in `importPDF` and error out otherwise.
        .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf, .data]) { result in
            switch result {
            case .success(let url): importPDF(url)
            case .failure: break // user cancelled the picker
            }
        }
    }
    #endif

    #if os(iOS)
    /// Decode the Setup Code QR out of the chosen Emergency Kit PDF and fill the field
    /// (the user confirms with Continue, same as the camera scan).
    private func importPDF(_ url: URL) {
        busy = true
        errorMessage = nil
        Task {
            defer { busy = false }
            if let key = await RecoveryKeyPDFImporter.extractRecoveryKey(from: url) {
                recoveryKey = key
            } else {
                errorMessage = appString("Couldn’t read a recovery key from that PDF. Try scanning the Setup Code instead.")
            }
        }
    }
    #endif

    private func dismissKeyboard() {
        PlatformAppearance.dismissKeyboard()
    }

    private func submit() {
        busy = true
        errorMessage = nil
        let entered = recoveryKey
        Task {
            defer { busy = false }
            let envelope: (wrapped: Data, salt: Data, kdf: KdfParams)
            do {
                envelope = try await VaultKeyEscrowService().fetchRecoveryEnvelope()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            do {
                // Heavy Argon2 unwrap runs off-main (same helper the unlock path uses).
                // A GCM authentication failure here means the key was mistyped.
                let key = try await VaultSession.unwrap(
                    wrapped: envelope.wrapped,
                    password: RecoveryKey.normalize(entered),
                    salt: Array(envelope.salt),
                    params: envelope.kdf)
                onKey(key, entered)
            } catch {
                errorMessage = appString("That recovery key didn’t work.")
            }
        }
    }
}

/// A single horizontal hairline, centred vertically — the solid "or" rule.
private struct DashLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

#if os(iOS)
/// Full-screen camera sheet that reads the Emergency Kit's Setup Code (a QR of the recovery
/// key) and hands the decoded string back to the recovery-entry field. Reuses the shared
/// `QRScannerView` (also used for TOTP import); the payload is the recovery key verbatim.
private struct RecoveryScannerSheet: View {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            QRScannerView { payload in
                let key = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { return }
                onScan(key)
            }
            .ignoresSafeArea()

            HStack {
                Button(action: onCancel) {
                    Text("Cancel").padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(.black.opacity(0.35), in: Capsule())
                .frame(minHeight: Metric.hitMin)
                Spacer()
                Text("Scan Setup Code")
                    .vaultType(.headline).foregroundStyle(.white)
                Spacer()
                Text("Cancel").padding(.horizontal, Space.s3).padding(.vertical, Space.s2).opacity(0)
            }
            .padding(Space.s4)
        }
    }
}
#endif
