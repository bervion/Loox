import SwiftUI

struct PasskeysScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selected: PasskeyInfo?
    @State private var quarantineSites = SharedConfig.quarantinedPasskeySites

    private var groups: [(site: String, passkeys: [PasskeyInfo])] {
        Dictionary(grouping: env.repository.passkeys, by: \.relyingParty)
            .map { (site: $0.key, passkeys: $0.value.sorted(by: newestFirst)) }
            .sorted { $0.site.localizedCaseInsensitiveCompare($1.site) == .orderedAscending }
    }

    var body: some View {
        Form {
            if !quarantineSites.isEmpty { quarantineSection }

            if groups.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label { Text("No passkeys yet") } icon: {
                            PolarisIcon(Icons.passkey, size: Metric.iconTileLarge)
                        }
                    } description: {
                        Text("Passkeys you create with Loox will appear here.")
                    }
                }
                .listRowBackground(VaultColors.surface)
            } else {
                ForEach(groups, id: \.site) { group in
                    Section(group.site) {
                        ForEach(group.passkeys) { passkey in
                            Button { selected = passkey } label: {
                                PasskeyRow(passkey: passkey)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(VaultColors.surface)
                }
            }
        }
        .themedFormBackground()
        .navigationTitle("Passkeys")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { PasskeyDetailSheet(passkey: $0) }
    }

    private var quarantineSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Some automatically created passkeys were invalid and removed.")
                    Text(quarantineSites.joined(separator: ", "))
                        .vaultType(.caption)
                        .themedForeground(.secondary)
                }
            } icon: {
                PolarisIcon(Icons.alert).foregroundStyle(env.theme.active.color(.warning))
            }
            Button("Dismiss") {
                SharedConfig.quarantinedPasskeySites = []
                quarantineSites = []
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    private func newestFirst(_ lhs: PasskeyInfo, _ rhs: PasskeyInfo) -> Bool {
        let left = lhs.lastUsedAt ?? lhs.createdAt
        let right = rhs.lastUsedAt ?? rhs.createdAt
        return left > right
    }
}

private struct PasskeyRow: View {
    let passkey: PasskeyInfo

    var body: some View {
        HStack(spacing: Space.s3) {
            FaviconView(urlString: "https://\(passkey.relyingParty)", category: .login, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(passkey.userName)
                    .vaultType(.body)
                    .themedForeground()
                    .lineLimit(1)
                Text(passkey.lastUsedAt ?? passkey.createdAt, style: .relative)
                    .vaultType(.caption)
                    .themedForeground(.secondary)
            }
            Spacer(minLength: Space.s2)
            PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
        }
        .contentShape(.rect)
    }
}
