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
                        if index < matches.count - 1 { Divider().padding(.leading, Space.s4) }
                    }
                }
                .background(VaultColors.surface)
                .vaultCornerRadius(Radius.md)
                // Same card treatment as the other detail-screen cards (fields,
                // shared-with) — elevation over a raw black/white stroke, so the
                // card definition tracks the live theme instead of a fixed color.
                .elevation(.level1)
            }
            .sheet(item: $selected) { PasskeyDetailSheet(passkey: $0) }
        }
    }

    private func row(_ passkey: PasskeyInfo) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(passkey.userName)
                    .vaultType(.body)
                    .themedForeground()
                    .lineLimit(1)
                Text("Created \(passkey.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .vaultType(.caption)
                    .themedForeground(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VaultIcon(Icons.personLockFilled, size: 22).foregroundStyle(Self.passkeyPurple)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        // Soft purple wash toward the trailing glyph (detail view only).
        .background(
            LinearGradient(
                colors: [.clear, Self.passkeyPurple.opacity(0.22)],
                startPoint: .center, endPoint: .trailing)
        )
        .contentShape(.rect)
    }

    /// Conventional passkey purple (violet), used only in the detail view.
    private static let passkeyPurple = Color(rgb: 0x8B5CF6)
}
