import SwiftUI
import UniformTypeIdentifiers

/// Shows the generated recovery key once, asks the one question that decides what that
/// key can do (iCloud Sync, nothing preselected), and requires the user to SAVE the
/// Emergency Kit PDF before continuing.
///
/// The step owns the recovery story, so it owns the consent: with sync off the kit resets
/// the MASTER PASSWORD ONLY, and only while this installation's vault and key bundle still
/// exist. Cross-device and device-loss recovery work only when sync is on AND the recovery
/// envelope actually uploaded, which is why turning sync on here AWAITS that upload and
/// reports success or failure instead of firing a silent best-effort sync.
struct EmergencyKitView: View {
    let recoveryKey: String
    /// Printed on the kit ("Created for …" + iCloud reminder). Threaded from the name step.
    var ownerName: String = ""
    var iCloudAccount: String = ""
    /// Set when generating the recovery key failed; the step then offers a retry instead
    /// of parking on a spinner that never resolves.
    var keyError: String?
    var onRetryKey: () -> Void = {}
    let onContinue: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The scope the SAVED PDF was printed with. Nil until a save succeeds; compared
    /// against the live scope so changing the sync answer after saving asks for a fresh
    /// kit rather than leaving printed instructions that no longer match.
    @State private var savedScope: EmergencyKitScope?
    /// The scope the exporter was handed, captured when the PDF bytes were built: the
    /// sync answer can change while the save sheet is open, and the file on disk is the
    /// older one.
    @State private var exportedScope: EmergencyKitScope = .thisInstallationOnly
    @State private var showExporter = false
    @State private var pdfFile: EmergencyKitPDFFile?
    @State private var exportError: String?
    /// Copy affordance feedback: flips the glyph to a green check for a beat.
    @State private var copiedKey = false
    @State private var sync = SyncConsentController()

    private var scope: EmergencyKitScope { sync.scope }
    private var savedPDF: Bool { savedScope == scope }

    private var info: EmergencyKitInfo {
        EmergencyKitInfo(recoveryKey: recoveryKey, ownerName: ownerName,
                         iCloudAccount: iCloudAccount, createdAt: .now, scope: scope)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    // Loox dots mark (the Home empty-avatar look), centred,
                    // revealing its rings on appear.
                    LooxDotsAvatar(size: 100, revealsOnAppear: true)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, Space.s6)
                    Text("Save your Emergency Kit")
                        .vaultType(.screenTitle)
                    Text("This recovery key is how you get back in if you forget your master password. Keep it somewhere safe and private.")
                        .vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s2)

                emergencyKitCard

                syncConsentSection

                kitScopeSection

                // Stakes, until the kit is saved — once saved the pinned
                // Continue is the only affordance left.
                if !savedPDF {
                    mustSaveWarning
                }

                if let exportError {
                    Text(exportError)
                        .vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s6)
            // Regular width (iPad/Mac): centered form column, not a full-screen stretch.
            .vaultContentWidth(.form)
        }
        // Onboarding concept: plain white page (the kit card carries its own surface).
        .background(Color(rgb: theme.background).ignoresSafeArea())
        // One pinned CTA slot like every other onboarding step: Save until the
        // PDF is actually saved, then Continue (a checkbox can't prove the key
        // was kept; a successful file save can). BOTH states use the same
        // component, so the label swap never changes the button's colour,
        // height, or position under the thumb.
        .safeAreaInset(edge: .bottom) {
            Group {
                if savedPDF {
                    BrandCapsuleCTA(action: onContinue)
                        .transition(.opacity)
                } else {
                    // Red is reserved for destructive actions; a red "Save" read
                    // as a warning instead of the way forward.
                    BrandCapsuleCTA(title: "Save Kit PDF",
                                    enabled: !recoveryKey.isEmpty && !sync.isUploading,
                                    action: presentExporter)
                }
            }
        }
        .fileExporter(isPresented: $showExporter,
                      document: pdfFile,
                      contentType: .pdf,
                      defaultFilename: info.suggestedFilename) { result in
            switch result {
            case .success:
                // Record WHICH kit was saved, not merely that one was.
                withAnimation(.vault(Motion.standard, reduceMotion: reduceMotion)) {
                    savedScope = exportedScope
                }
                exportError = nil
                Haptics.success()
            case .failure(let error):
                // A user cancel also lands here as CocoaError.userCancelled — not a real error.
                if (error as NSError).code != NSUserCancelledError {
                    exportError = appString("Couldn’t save the Emergency Kit. Please try again.")
                }
            }
        }
    }

    // MARK: iCloud Sync consent

    /// Two options, neither preselected, and no answer means no upload. The default the
    /// app ships with (`iCloudSyncEnabled == false`) is the safe one, so a user who walks
    /// past this question keeps everything local.
    @ViewBuilder private var syncConsentSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Do you want iCloud Sync?")
                .vaultType(.headline)
            Text("This is the only setting that decides whether your Emergency Kit can rebuild your vault somewhere else.")
                .vaultType(.footnote).themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            consentOption(
                selected: sync.consent == .granted,
                title: "Turn on iCloud Sync",
                detail: "Your items upload end to end encrypted, and your Emergency Kit can restore this vault on a new device. Folder icons, colors, order, timestamps, and your device name travel as ordinary iCloud data.",
                action: grantSync)

            consentOption(
                selected: sync.consent == .declined,
                title: "Keep this device only",
                detail: "Nothing leaves this device. Your Emergency Kit then resets the master password here, and cannot bring the vault back once this device is gone.",
                action: declineSync)

            uploadStatus
        }
    }

    private func consentOption(selected: Bool,
                               title: LocalizedStringKey,
                               detail: LocalizedStringKey,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Space.s3) {
                VaultIcon(selected ? Icons.checkCircle : "sf:circle", size: Metric.iconInline)
                    .foregroundStyle(selected ? Color(rgb: theme.accent) : theme.color(.iconSecondary))
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(title)
                        .vaultType(.callout).fontWeight(.semibold).themedForeground(.primary)
                    Text(detail)
                        .vaultType(.footnote).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, minHeight: Metric.hitMin, alignment: .leading)
            .background(Color(rgb: selected ? theme.accentSoft : theme.secondaryBackground),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Color(rgb: theme.accent).opacity(selected ? 0.55 : 0),
                              lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sync.isUploading)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The awaited upload, reported. "Turned on" is not the same as "your kit works
    /// somewhere else", and the difference only shows up when the device is already lost.
    @ViewBuilder private var uploadStatus: some View {
        switch sync.upload {
        case .notStarted:
            EmptyView()
        case .uploading:
            HStack(spacing: Space.s2) {
                ProgressView()
                Text("Sending your recovery file to iCloud")
                    .vaultType(.footnote).themedForeground(.secondary)
            }
            .frame(minHeight: Metric.hitMin, alignment: .leading)
        case .uploaded:
            VaultInfoBanner(.info, icon: Icons.checkCircle,
                            text: "Your recovery file reached iCloud. This kit can now restore your vault on a new device.")
        case .failed(let reason):
            VaultInfoBanner(.error,
                            title: "Your recovery file did not reach iCloud",
                            verbatimText: reason,
                            actionLabel: "Try again",
                            action: retryUpload)
        }
    }

    // MARK: What the kit can do

    /// Explicitly a `LocalizedStringKey`: a bare ternary of two literals inside `Text`
    /// can resolve to the verbatim `StringProtocol` overload, which silently skips the
    /// catalog and ships this sentence in English to every locale.
    private var scopeText: LocalizedStringKey {
        scope == .crossDevice
            ? "It resets your master password on this device, and restores your vault on a new device signed in to the same iCloud account. Turn iCloud Sync off later and it goes back to this device only."
            : "It resets your master password for the vault on this device, and only while Loox and this vault are still installed here. It is not a backup: after device loss, deleting the app, or setting up a new device, this kit cannot bring your vault back."
    }

    /// Always on screen and always accurate, because this is the sentence the user will
    /// remember when they need the kit.
    private var kitScopeSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("What this kit can do")
                .vaultType(.headline)
            Text(scopeText)
                .vaultType(.footnote).themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let savedScope, savedScope != scope {
                Text("Your saved kit was printed before this change. Save it again so the instructions on the page match.")
                    .vaultType(.footnote).themedForeground(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: theme.secondaryBackground),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Actions

    private func grantSync() {
        Task {
            await sync.grant(apply: applySyncFlag) {
                try await VaultKeyEscrowService().pushRecoveryEnvelope()
            }
            // The seeded Space and identity posted their mutations while the flag was
            // still off, so the coordinator's debounce never armed for them. Without
            // this nudge the first item sync waits for an unrelated later trigger.
            env.syncNow()
        }
    }

    private func declineSync() {
        sync.decline(apply: applySyncFlag)
    }

    private func retryUpload() {
        Task {
            await sync.retry { try await VaultKeyEscrowService().pushRecoveryEnvelope() }
        }
    }

    /// The one place onboarding is allowed to move the sync flag, and only from a tap.
    /// Logged as a user toggle here rather than in the store's didSet, which also fires
    /// for erase and other programmatic writes.
    private func applySyncFlag(_ isOn: Bool) {
        env.settings.iCloudSyncEnabled = isOn
        AnalyticsEngine.shared.log(.icloudSyncToggled(enabled: isOn))
        AnalyticsEngine.shared.setUserProperty(.icloudSync, isOn ? "on" : "off")
    }

    private func presentExporter() {
        guard let data = EmergencyKitPDF.makeData(info) else {
            exportError = appString("Couldn’t build the Emergency Kit PDF. Please try again.")
            return
        }
        pdfFile = EmergencyKitPDFFile(data: data)
        exportedScope = scope
        showExporter = true
    }

    private func copyKey() {
        guard !recoveryKey.isEmpty else { return }
        env.clipboard.copy(recoveryKey, label: appString("recovery key"), sensitive: true)
        withAnimation(.easeInOut(duration: 0.15)) { copiedKey = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.2)) { copiedKey = false }
        }
    }

    // MARK: Emergency Kit card (concept design)

    /// Branded kit card: blue header with a Share chip, owner + created-date columns,
    /// and the recovery key in a dashed focal box that copies on tap. No infinity mark.
    private var emergencyKitCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Emergency Kit")
                    .vaultType(.footnote).fontWeight(.semibold)
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(.white)
                Spacer()
                if !recoveryKey.isEmpty {
                    ShareLink(item: recoveryKey) {
                        HStack(spacing: Space.s1) {
                            VaultIcon(Icons.share, size: 13)
                            Text("Share").vaultType(.caption).fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Space.s3)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.22), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [.looxRoyal, .looxBlue],
                                       startPoint: .leading, endPoint: .trailing))

            VStack(alignment: .leading, spacing: Space.s4) {
                recoveryKeyBox
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: theme.elevatedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        // The page is white, so the kit card needs the white-canvas shadow.
        .elevation(.cardOnWhite)
    }

    /// Dashed focal box; the whole box copies the key on tap (the clipboard
    /// service raises the "copied" toast), with a copy glyph in the top corner.
    private var recoveryKeyBox: some View {
        VStack(spacing: Space.s2) {
            // Label row: the copy glyph rides the SAME line as the label, so the
            // two sit vertically centred together; it flips to a green check
            // for a beat after copying.
            ZStack {
                Text("Recovery Key")
                    .vaultType(.caption).fontWeight(.semibold)
                    .textCase(.uppercase).tracking(1)
                    .themedForeground(.tertiary)
                if !recoveryKey.isEmpty {
                    HStack {
                        Spacer()
                        VaultIcon(copiedKey ? Icons.checkCircle : Icons.copy, size: Metric.iconInline)
                            .foregroundStyle(copiedKey ? Color(rgb: theme.success)
                                                       : theme.color(.iconSecondary))
                    }
                }
            }
            keyText
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
        .padding(.horizontal, Space.s3)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Color(rgb: theme.destructive).opacity(0.55),
                          style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .contentShape(Rectangle())
        .onTapGesture { copyKey() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Copies the recovery key"))
    }

    /// Generation is one Argon2 wrap away from the key existing, but when it fails the
    /// step used to sit on a spinner with no way out and no way back — the CTA is
    /// disabled on an empty key and this screen has no back control.
    @ViewBuilder private var keyText: some View {
        if let keyError {
            VStack(spacing: Space.s3) {
                Text(verbatim: keyError)
                    .vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onRetryKey) {
                    Text("Try again")
                        .vaultType(.body).fontWeight(.medium)
                        .themedForeground(.accentText)
                        .frame(maxWidth: .infinity, minHeight: Metric.hitMin)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        } else if recoveryKey.isEmpty {
            ProgressView().frame(minHeight: Metric.hitMin)
        } else {
            Text(displayKey)
                .font(.vaultCode(.title3, weight: .semibold))
                .tracking(0.5)
                .lineSpacing(Space.s2)
                .multilineTextAlignment(.center)
                .themedForeground(.primary)
        }
    }

    /// Quiet duotone note (matches the info notes elsewhere) shown until the
    /// kit is saved — the stakes read without shouting.
    private var mustSaveWarning: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Image("HandHoldingMedicalDuotone")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
            Text("Save the kit to continue. Without it, a forgotten master password cannot be reset.")
                .vaultType(.footnote).themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Space.s2)
    }

    /// Split the hyphenated key into two balanced lines so it reads as a block instead of
    /// wrapping wherever the screen width happens to break it. Copy always uses the raw value.
    private var displayKey: String {
        let groups = recoveryKey.split(separator: "-")
        guard groups.count >= 4 else { return recoveryKey }
        let mid = (groups.count + 1) / 2
        return groups[..<mid].joined(separator: "-") + "-\n" + groups[mid...].joined(separator: "-")
    }
}
