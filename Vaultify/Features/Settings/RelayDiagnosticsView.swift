#if DEBUG
import Foundation
import SwiftUI

/// A read-only view of relay setup and the sanitized local diagnostic log.
/// Clearing the log does not change the principal, device keys or alias state.
struct RelayDiagnosticsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var text = ""
    @State private var configurationExpanded = false
    @State private var confirmClear = false

    private var copied: Bool { env.clipboard.recentCopyLabel == appString("diagnostic log") }

    var body: some View {
        Form {
            Section {
                DisclosureGroup("Configuration", isExpanded: $configurationExpanded) {
                    metadataRow("App version", value: appVersion)
                    metadataRow("Relay host", value: RelayConfig.apiBaseURL.host ?? appString("Unavailable"))
                    metadataRow("App Attest environment", value: AppAttestEnvironment.current.rawValue)
                    metadataRow("App Attest supported", value: RelayAttestation.isSupported
                                ? appString("Supported") : appString("Unsupported"))
                }
                .vaultType(.body)
                .themedForeground()
            }
            .listRowBackground(VaultColors.surface)

            Section {
                if text.isEmpty {
                    Text("No relay diagnostics yet. Try the Private Email action again, then refresh this log.")
                        .vaultType(.body)
                        .themedForeground(.secondary)
                } else {
                    Text(verbatim: text)
                        .vaultType(.footnote)
                        .themedForeground()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Diagnostic log")
                    .vaultType(.sectionLabel)
                    .themedForeground(.secondary)
            } footer: {
                Text("Diagnostics are stored only in Debug. The log records technical steps without email addresses or vault data.")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle(Text(LocalizedStringResource("Private Email diagnostics").inAppLocalized))
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    reload()
                    guard !text.isEmpty else { return }
                    env.clipboard.copy(text, label: appString("diagnostic log"), sensitive: false)
                } label: {
                    CopyMorphIcon(copied: copied)
                        .themedForeground(text.isEmpty ? .iconDisabled : .accentText)
                        .frame(minWidth: Metric.hitMin, minHeight: Metric.hitMin)
                }
                .disabled(text.isEmpty)
                .accessibilityLabel(Text("Copy log"))
                .accessibilityValue(Text(verbatim: copied ? appString("Copied") : ""))

                Menu {
                    Button {
                        reload()
                    } label: {
                        Label { Text("Refresh") } icon: { VaultIcon(Icons.refresh) }
                    }
                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label { Text("Clear log") } icon: { VaultIcon(Icons.trash) }
                    }
                    .disabled(text.isEmpty)
                } label: {
                    VaultIcon(Icons.moreHorizontal)
                        .themedForeground(.iconPrimary)
                        .frame(minWidth: Metric.hitMin, minHeight: Metric.hitMin)
                }
                .accessibilityLabel(Text("Log actions"))
            }
        }
        .confirmationDialog("Clear relay diagnostics?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear log", role: .destructive) {
                RelayDiagnostics.clear()
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes only the local diagnostic log.")
        }
        .refreshable { reload() }
        .task { reload() }
    }

    /// Stacked metadata keeps long Vietnamese labels and host names readable
    /// at narrow widths and accessibility text sizes.
    private func metadataRow(_ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label).vaultType(.subhead).themedForeground(.secondary)
            Text(verbatim: value).vaultType(.body).themedForeground()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let revision = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let version else { return appString("Unavailable") }
        return revision.map { "\(version) (\($0))" } ?? version
    }

    private func reload() { text = RelayDiagnostics.contents() }
}
#endif
