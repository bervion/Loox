import SwiftUI

/// iCloud sync controls. Sync is opt-in; it uploads only sealed ciphertext.
struct SyncSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { env.settings.iCloudSyncEnabled },
            set: { isOn in
                env.settings.iCloudSyncEnabled = isOn
                if isOn { env.syncNow() }
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: syncBinding) {
                    Label { Text("iCloud Sync") } icon: { PolarisIcon(Icons.sync) }
                }
            } footer: {
                Text("Items are end-to-end encrypted before they sync. iCloud stores only ciphertext — neither Apple nor anyone else can read your vault.")
            }
            .listRowBackground(VaultColors.surface)

            if !CloudSyncService.isConfigured {
                Section {
                    Label {
                        Text("To use iCloud Sync, enable the iCloud capability (CloudKit) for the app target in Xcode and sign in to iCloud on this device.")
                            .font(.footnote).themedForeground(.secondary)
                    } icon: {
                        PolarisIcon(Icons.info).foregroundStyle(VaultColors.strengthMedium)
                    }
                }
                .listRowBackground(VaultColors.surface)
            }

            if env.settings.iCloudSyncEnabled {
                Section {
                    Button { env.syncNow() } label: {
                        Label { Text("Sync Now") } icon: { PolarisIcon(Icons.refresh) }
                    }
                    .disabled(env.cloudSync.status == .syncing)
                    statusRow
                }
                .listRowBackground(VaultColors.surface)
            }
        }
        .themedFormBackground()
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var statusRow: some View {
        switch env.cloudSync.status {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: Space.s2) { ProgressView(); Text("Syncing…").themedForeground(.secondary) }
        case .success(let date):
            LabeledContent("Last sync", value: date.formatted(date: .omitted, time: .shortened))
        case .error(let message):
            Text(message).font(.footnote).foregroundStyle(VaultColors.strengthWeak)
        }
    }
}
