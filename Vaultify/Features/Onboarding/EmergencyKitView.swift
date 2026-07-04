import SwiftUI
import UniformTypeIdentifiers

/// Shows the generated recovery key once and requires the user to SAVE the Emergency Kit
/// PDF before continuing — it is the only way to recover a forgotten master password / set
/// up a new device. Layout mirrors the other onboarding steps: top-aligned, left-aligned,
/// Loox brand mark, the key as the focal card, soft tinted actions.
struct EmergencyKitView: View {
    let recoveryKey: String
    /// Printed on the kit ("Created for …" + iCloud reminder). Threaded from the name step.
    var ownerName: String = ""
    var iCloudAccount: String = ""
    let onContinue: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.appTheme) private var theme
    @State private var savedPDF = false
    @State private var showExporter = false
    @State private var pdfFile: EmergencyKitPDFFile?
    @State private var exportError: String?

    private var info: EmergencyKitInfo {
        EmergencyKitInfo(recoveryKey: recoveryKey, ownerName: ownerName,
                         iCloudAccount: iCloudAccount, createdAt: .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    BrandLogoMark.compact
                    Text("Save your Emergency Kit")
                        .vaultType(.screenTitle)
                    Text("This recovery key can restore your vault if you forget your master password or set up a new device. Save the PDF to continue.")
                        .vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s2)

                VStack(spacing: Space.s3) {
                    keyCard
                    HStack(spacing: Space.s3) {
                        Button {
                            env.clipboard.copy(recoveryKey, label: "Recovery key", sensitive: true)
                        } label: {
                            tintedActionLabel("Copy", icon: Icons.copy)
                        }
                        .buttonStyle(.themedTinted)

                        if !recoveryKey.isEmpty {
                            ShareLink(item: recoveryKey) {
                                tintedActionLabel("Share", icon: Icons.share)
                            }
                            .buttonStyle(.themedTinted)
                        }
                    }
                }

                savePDFCard

                if let exportError {
                    Text(exportError)
                        .vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s6)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .disabled(!savedPDF || recoveryKey.isEmpty)
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.gutter)
        }
        .fileExporter(isPresented: $showExporter,
                      document: pdfFile,
                      contentType: .pdf,
                      defaultFilename: info.suggestedFilename) { result in
            switch result {
            case .success:
                savedPDF = true
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

    private func tintedActionLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        Label { Text(title) } icon: { PolarisIcon(icon, size: Metric.iconInline) }
            .frame(maxWidth: .infinity)
    }

    private var keyCard: some View {
        Group {
            if recoveryKey.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 88)
            } else {
                Text(displayKey)
                    .font(.vaultCode(.title3, weight: .semibold))
                    .tracking(0.5)
                    .lineSpacing(Space.s2)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Space.s6)
                    .padding(.horizontal, Space.s3)
            }
        }
        .background(Color(rgb: theme.elevatedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .elevation(.level2)
    }

    /// Required action: build + save the kit PDF. Once saved, the card confirms and the
    /// bottom Continue button unlocks. A checkbox alone can't prove the key was preserved;
    /// a successful file save can.
    private var savePDFCard: some View {
        Button(action: presentExporter) {
            HStack(alignment: .center, spacing: Space.s3) {
                PolarisIcon(savedPDF ? Icons.checkCircle : Icons.shield, size: Metric.iconUtility)
                    .foregroundStyle(savedPDF ? VaultColors.strengthStrong : Color(rgb: theme.accent))
                    .frame(width: Metric.controlLarge, height: Metric.controlLarge)
                    .background(Color(rgb: theme.accentSoft),
                                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(savedPDF ? "Emergency Kit saved" : "Save Emergency Kit (PDF)")
                        .vaultType(.headline)
                    Text(savedPDF
                         ? "Keep it somewhere safe and offline."
                         : "Save the printable PDF with your recovery key and Setup Code.")
                        .vaultType(.footnote).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Space.s2)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: theme.elevatedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .elevation(.level2)
        }
        .buttonStyle(.plain)
        .disabled(recoveryKey.isEmpty)
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
