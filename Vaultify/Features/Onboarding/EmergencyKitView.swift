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

    private var info: EmergencyKitInfo {
        EmergencyKitInfo(recoveryKey: recoveryKey, ownerName: ownerName,
                         iCloudAccount: iCloudAccount, createdAt: .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    BrandLockup(height: 38)
                    Text("Save your Emergency Kit")
                        .vaultType(.screenTitle)
                    Text("This recovery key can restore your vault if you forget your master password or set up a new device.")
                        .vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s2)

                emergencyKitCard

                // Required action + gated continue. Continue only appears once the
                // PDF is actually saved (a checkbox can't prove the key was kept);
                // until then an amber warning states the stakes.
                VStack(spacing: Space.s3) {
                    saveButton

                    if savedPDF {
                        Button(action: onContinue) {
                            Text("Continue").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.themedProminent)
                        .controlSize(.large)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        mustSaveWarning
                    }
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
        env.clipboard.copy(recoveryKey, label: "Recovery key", sensitive: true)
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
                HStack(alignment: .top) {
                    cardField(label: "Owner", value: ownerName.isEmpty ? "—" : ownerName,
                              alignment: .leading)
                    Spacer()
                    cardField(label: "Created", value: createdDateString, alignment: .trailing)
                }

                recoveryKeyBox
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: theme.elevatedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .elevation(.level2)
    }

    /// Dashed focal box; the whole box copies the key on tap (the clipboard
    /// service raises the "copied" toast), with a copy glyph in the top corner.
    private var recoveryKeyBox: some View {
        VStack(spacing: Space.s2) {
            Text("Recovery Key")
                .vaultType(.caption).fontWeight(.semibold)
                .textCase(.uppercase).tracking(1)
                .themedForeground(.tertiary)
            keyText
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s5)
        .padding(.horizontal, Space.s3)
        .overlay(alignment: .topTrailing) {
            if !recoveryKey.isEmpty {
                PolarisIcon(Icons.copy, size: Metric.iconInline)
                    .themedForeground(.iconSecondary)
                    .padding(Space.s3)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(Color.looxBlue.opacity(0.4),
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

    private func cardField(label: LocalizedStringKey, value: String,
                           alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: Space.s1) {
            Text(label)
                .vaultType(.caption).fontWeight(.semibold)
                .textCase(.uppercase).tracking(1)
                .themedForeground(.tertiary)
            Text(value)
                .vaultType(.callout).fontWeight(.medium)
                .themedForeground(.primary)
        }
    }

    private var createdDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: Date.now)
    }

    // MARK: Save action (brand blue) — reveals Continue on success

    private var saveButton: some View {
        Button(action: presentExporter) {
            HStack(spacing: Space.s2) {
                // SF download glyph here (user-approved exception to Polaris-only);
                // the saved state keeps the Polaris check mark.
                if savedPDF {
                    PolarisIcon(Icons.checkCircle, size: Metric.iconInline)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: Metric.iconInline, weight: .semibold))
                }
                Text(savedPDF ? "Emergency Kit saved" : "Save Kit PDF")
                    .vaultType(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s4)
            .background(saveButtonFill)
            .vaultCornerRadius(Radius.sm)
            .opacity(recoveryKey.isEmpty ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(recoveryKey.isEmpty)
    }

    @ViewBuilder private var saveButtonFill: some View {
        if savedPDF {
            VaultColors.strengthStrong
        } else {
            LinearGradient(colors: [.looxRoyal, .looxBlue], startPoint: .leading, endPoint: .trailing)
        }
    }

    /// Amber "you must save this" card (with an alert glyph) shown under the Save
    /// button until the kit is saved — the stakes read immediately, in place.
    private var mustSaveWarning: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            PolarisIcon(Icons.alert, size: Metric.iconUtility)
                .foregroundStyle(Color(rgb: theme.warning))
            Text("Save the kit to continue. It is the only way to recover your vault.")
                .vaultType(.footnote).themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: theme.warningSoft),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
