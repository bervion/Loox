import SwiftUI

/// Shown while the search field is empty: Recently Used items (respecting the
/// current scope) plus quick filter chips that seed a scoped operator search
/// with a single tap — no typing required. Replaces the prior dead
/// `ContentUnavailableView`. All local, no network, no AI.
struct SearchZeroStateView: View {
    @Environment(AppEnvironment.self) private var env
    let scope: SpaceScope
    /// Invoked with an `SearchOperator` keyword to seed into the search field —
    /// the existing token-AND + operator pipeline then does the actual filtering.
    let onSelectFilter: (String) -> Void

    private var recents: [VaultItem] {
        switch scope {
        case .sharedWithMe:
            return [] // shared projections carry no local `lastUsedAt` signal
        case .thisSpace(let id):
            return env.repository.recentlyUsed(folder: id, limit: 6)
        case .allSpaces:
            return env.repository.recentlyUsed(folder: nil, limit: 6)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                filterChips
                if !recents.isEmpty { recentsSection }
            }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.s3)
            .padding(.bottom, Space.s7)
        }
        .scrollIndicators(.hidden)
    }

    private var filterChips: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Quick filters")
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    SearchFilterChip(icon: Icons.clock, title: Text(FieldKind.totp.title)) { onSelectFilter("2fa") }
                    SearchFilterChip(icon: Icons.passkey, title: Text("Passkeys")) { onSelectFilter("passkey") }
                    SearchFilterChip(icon: Icons.creditCard, title: Text(ItemCategory.card.title)) { onSelectFilter("card") }
                    SearchFilterChip(icon: Icons.alert, title: Text("Weak")) { onSelectFilter("weak") }
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Recently Used")
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(recents.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: item.id) {
                        VaultItemRow(item: item, showSpace: scope == .allSpaces)
                    }
                    .buttonStyle(.plain)
                    if index < recents.count - 1 { Divider().padding(.leading, Space.gutter) }
                }
            }
            .background(VaultColors.surface)
            .vaultCornerRadius(Radius.md)
        }
    }
}

/// A single quick-filter chip: icon + localized label, seeds the search field
/// with an operator keyword on tap.
private struct SearchFilterChip: View {
    @Environment(AppEnvironment.self) private var env
    let icon: String
    let title: Text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s1) {
                PolarisIcon(icon, size: Metric.iconInline)
                title.vaultType(.footnote)
            }
            .themedForeground(.secondary)
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .frame(minHeight: Metric.hitMin)
            .background(Color(rgb: env.theme.active.surfacePressed), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
