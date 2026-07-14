import SwiftUI

/// "Backup" — the import / export data-portability tools gathered into one child
/// screen (they both move the whole vault in and out of a file).
struct BackupSettingsView: View {
    var body: some View {
        Form {
            Section {
                NavigationLink { ImportView() } label: {
                    Label { Text("Import") } icon: { SettingsIconBadge(systemName: "square.and.arrow.down.fill", tint: SettingsBadgeTint.teal) }
                }
                NavigationLink { ExportView() } label: {
                    Label { Text("Export") } icon: { SettingsIconBadge(systemName: "square.and.arrow.up.fill", tint: SettingsBadgeTint.orange) }
                }
            } footer: {
                Text("Import from another password manager, or export your whole vault to a file you control.")
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle("Backup")
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}
