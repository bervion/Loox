import SwiftUI
import UniformTypeIdentifiers

/// Shows the generated recovery key once and requires the user to SAVE the Emergency Kit
/// PDF before continuing — it is the only way to recover a forgotten master password / set
/// up a new device. The key rides in a branded Emergency Kit card (tap to copy, Share chip
/// in the header); the blue Save action exports the PDF, and the black Continue button stays
/// hidden behind an amber "must save" warning until the save succeeds.
struct EmergencyKitView: View {
    let recoveryKey: String
    /// Printed on the kit ("Created for …" + iCloud reminder). Threaded from the name step.
    var ownerName: String = ""
    var iCloudAccount: String = ""
    let onContinue: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var savedPDF = false
    @State private var showExporter = false
    @State private var pdfFile: EmergencyKitPDFFile?
    @State private var exportError: String?
    /// Copy affordance feedback: flips the glyph to a green check for a beat.
    @State private var copiedKey = false

    private var info: EmergencyKitInfo {
        EmergencyKitInfo(recoveryKey: recoveryKey, ownerName: ownerName,
                         iCloudAccount: iCloudAccount, createdAt: .now)
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
                    Text("This recovery key can restore your vault if you forget your master password or set up a new device.")
                        .vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s2)

                emergencyKitCard

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
        }
        // Onboarding concept: plain white page (the kit card carries its own surface).
        .background(Color(rgb: theme.background).ignoresSafeArea())
        // One pinned CTA slot like every other onboarding step: Save until the
        // PDF is actually saved, then Continue (a checkbox can't prove the key
        // was kept; a successful file save can).
        .safeAreaInset(edge: .bottom) {
            Group {
                if savedPDF {
                    BrandCapsuleCTA(action: onContinue)
                        .transition(.opacity)
                } else {
                    saveButton
                        .padding(.horizontal, Space.s6)
                        .padding(.bottom, Space.s4)
                }
            }
        }
        .fileExporter(isPresented: $showExporter,
                      document: pdfFile,
                      contentType: .pdf,
                      defaultFilename: info.suggestedFilename) { result in
            switch result {
            case .success:
                withAnimation(.vault(Motion.standard, reduceMotion: reduceMotion)) { savedPDF = true }
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

    private func presentExporter() {
        guard let data = EmergencyKitPDF.makeData(info) else {
            exportError = appString("Couldn’t build the Emergency Kit PDF. Please try again.")
            return
        }
        pdfFile = EmergencyKitPDFFile(data: data)
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
                            PolarisIcon(Icons.share, size: 13)
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
                        PolarisIcon(copiedKey ? Icons.checkCircle : Icons.copy, size: Metric.iconInline)
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

    @ViewBuilder private var keyText: some View {
        if recoveryKey.isEmpty {
            ProgressView().frame(minHeight: 44)
        } else {
            Text(displayKey)
                .font(.vaultCode(.title3, weight: .semibold))
                .tracking(0.5)
                .lineSpacing(Space.s2)
                .multilineTextAlignment(.center)
                .themedForeground(.primary)
        }
    }

    // MARK: Save action (brand blue) — reveals Continue on success

    private var saveButton: some View {
        Button(action: presentExporter) {
            Text("Save Kit PDF")
                .vaultType(.body).fontWeight(.medium)
            // Full-width accent capsule: this is the screen's one primary action.
            // Red is reserved for destructive actions; a red "Save" read as a
            // warning instead of the way forward. (Once saved, the pinned slot
            // flips to Continue.)
            .foregroundStyle(Color(rgb: theme.accentForeground))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s3)
            .background(Color(rgb: theme.accent), in: Capsule())
            .opacity(recoveryKey.isEmpty ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(recoveryKey.isEmpty)
    }

    /// Quiet duotone note (matches the info notes elsewhere) shown until the
    /// kit is saved — the stakes read without shouting.
    private var mustSaveWarning: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Image("HandHoldingMedicalDuotone")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
            Text("Save the kit to continue. It is the only way to recover your vault.")
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
