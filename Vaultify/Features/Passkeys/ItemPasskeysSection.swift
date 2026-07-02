import SwiftUI

struct ItemPasskeysSection: View {
    let item: VaultItem
    @Environment(AppEnvironment.self) private var env
    @State private var selected: PasskeyInfo?

    private var matches: [PasskeyInfo] {
        guard item.category == .login, item.autofillHost != nil else { return [] }
        return env.repository.passkeys
            .filter { item.matchesRelyingParty($0.relyingParty) }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    var body: some View {
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Passkeys")
                    .vaultType(.sectionLabel)
                    .themedForeground(.secondary)
                    .padding(.horizontal, Space.s1)
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, passkey in
                        Button { selected = passkey } label: {
                            row(passkey)
                        }
                        .buttonStyle(.plain)
                        if index < matches.count - 1 { Divider().padding(.leading, Space.gutter) }
                    }
                }
                .background(VaultColors.surface)
                .vaultCornerRadius(Radius.md)
            }
            .sheet(item: $selected) { PasskeyDetailSheet(passkey: $0) }
        }
    }

    private func row(_ passkey: PasskeyInfo) -> some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(Icons.passkey, size: Metric.iconInline)
                .themedForeground(.secondary)
                .frame(width: Metric.iconUtility, height: Metric.iconUtility)
            VStack(alignment: .leading, spacing: 2) {
                Text(passkey.userName)
                    .vaultType(.body)
                    .themedForeground()
                    .lineLimit(1)
                Text(passkey.relyingParty)
                    .vaultType(.caption)
                    .themedForeground(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
        }
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s3)
        .contentShape(.rect)
    }
}
