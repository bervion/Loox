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
        VStack(spacing: 0) {
            header
            content
        }
        .animation(.vault(.smooth(duration: 0.35), reduceMotion: reduceMotion), value: step)
        // Backing out of the password step abandons the hand-off — drop the key
        // (SecureBytes deinit zeroes it) instead of leaving it parked in state.
        .onChange(of: step) { _, newStep in
            if newStep == .entry { clearReceivedKey() }
        }
    }

    /// Standard presented-flow header: a single leading back control (chevron), no
    /// title (each step carries its own brand header). Hidden on the terminal
    /// biometric step, where going back after a successful join makes no sense.
    @ViewBuilder private var header: some View {
        if step != .biometric {
            HStack {
                Button(action: back) {
                    PolarisIcon(Icons.chevronLeft, size: Metric.iconUtility)
                        .themedForeground(.iconPrimary)
                        .frame(width: Metric.hitMin, height: Metric.hitMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
                Spacer()
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s2)
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Space.s5) {
            HStack {
                Button { dismiss() } label: {
                    PolarisIcon(Icons.closeCircle, size: 28)
                        .themedForeground(.iconSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))
                Spacer()
            }

            VStack(spacing: Space.s2) {
                Text("Restore data")
                    .vaultType(.section)
                Text("Move your vault from another device, or reopen it with your Emergency Kit.")
                    .vaultType(.subhead).themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: Space.s3) {
                JoinOptionCard(icon: Icons.scanCode,
                               title: "Pair with an old device",
                               detail: "Scan a QR code between two iPhones to move the whole vault.",
                               action: onQR)
                JoinOptionCard(icon: Icons.key,
                               title: "Use Recovery Key",
                               detail: "Enter the key printed in the Emergency Kit (PDF) you saved.",
                               action: onRecovery)
            }

            Text("All decryption happens on this device. Loox never sees your data.")
                .vaultType(.footnote).themedForeground(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct JoinOptionCard: View {
    let icon: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    let action: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Space.s4) {
                PolarisIcon(icon, size: Metric.iconUtility)
                    .foregroundStyle(VaultColors.accent)
                    .frame(width: Metric.controlLarge, height: Metric.controlLarge)
                    .background(Color(rgb: env.theme.active.accentSoft),
                                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(title.inAppLocalized).vaultType(.callout).fontWeight(.semibold)
                        .themedForeground(.primary)
                    Text(detail.inAppLocalized).vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                PolarisIcon(Icons.chevronRight, size: Metric.iconInline)
                    .themedForeground(.iconSecondary)
            }
            .padding(Space.s4)
            .background(VaultColors.surface,
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .elevation(.level2)
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
                Spacer(minLength: Space.s6)
                OnboardingStepHeader(
                    "Pair with QR Code",
                    subtitle: "On your other device, open Settings → iCloud Sync → Pair New Device, then scan this code.",
                    style: .compact)

                QRCodeView(payload: session.qrPayload)
                    .frame(maxWidth: 260)
                    .padding(.top, Space.s6)

                Group {
                    if let errorMessage {
                        Text(errorMessage)
                            .vaultType(.footnote)
                            .foregroundStyle(VaultColors.strengthWeak)
                            .multilineTextAlignment(.center)
                    } else {
                        HStack(spacing: Space.s2) {
                            ProgressView()
                            Text("Waiting for your other device…")
                                .vaultType(.subhead).themedForeground(.secondary)
                        }
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
                        Text("Start Over").frame(maxWidth: .infinity)
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
                Spacer(minLength: Space.s6)
                OnboardingStepHeader(
                    "Use Recovery Key",
                    subtitle: "Import your saved Emergency Kit PDF, scan its Setup Code, or type the recovery key. Your vault will download from iCloud.",
                    style: .compact)

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
                VStack(spacing: Space.s3) {
                    Button(action: submit) {
                        Group {
                            if busy { ProgressView() } else { Text("Continue") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                    .controlSize(.large)
                    .disabled(recoveryKey.isEmpty || busy)

                    #if os(iOS)
                    Button { showPDFImporter = true } label: {
                        Label {
                            Text("Import from PDF")
                        } icon: {
                            Image(systemName: "arrow.down.doc")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedTinted)
                    .controlSize(.large)
                    .disabled(busy)
                    #endif
                }
                .padding(.horizontal, Space.s6)
                .padding(.bottom, Space.s6)
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showScanner) {
            RecoveryScannerSheet { scanned in
                recoveryKey = scanned
                showScanner = false
            } onCancel: { showScanner = false }
        }
        .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): importPDF(url)
            case .failure: break // user cancelled the picker
            }
        }
        #endif
    }

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
