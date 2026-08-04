import SwiftUI

/// A customizable section on the Home screen. The raw value is the stable identifier
/// persisted in `SettingsStore.homeSectionOrder` / `homeHiddenSections`; the `allCases`
/// sequence is the default (first-run) layout.
///
/// The profile row is deliberately NOT a case — it stays pinned at the top and is never
/// hidden or reordered. Every other section can be shown, hidden, and reordered from the
/// Home layout editor (`HomeLayoutEditor`).
/// MainActor-isolated (project default): its `icon` reads the MainActor `Icons` constants
/// and it's only ever composed on the main thread by the Home views.
enum HomeSection: String, CaseIterable, Identifiable, Sendable {
    /// Leads the default layout, directly under the pinned profile row (owner
    /// decision 260730). A saved order still wins — a user who moved the sections
    /// themselves keeps their arrangement.
    case quickActions
    case pendingShares
    case approvals
    case totp
    case attention
    case recentlyUsed
    case favorites
    case allItems

    var id: String { rawValue }

    /// Localized name shown in the layout editor. Pinned to the in-app language, and reuses
    /// the same string keys as the on-screen section headers so the two never drift.
    var title: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .pendingShares: "Pending Shares"
        case .approvals: "Approval Requests"
        case .totp: "Authenticator Codes"
        case .attention: "Needs Attention"
        case .recentlyUsed: "Recently Used"
        case .favorites: "Favorites"
        case .allItems: "All Items"
        case .quickActions: "Quick Actions"
        }
        return base.inAppLocalized
    }

    /// Polaris glyph shown beside the name in the layout editor.
    var icon: String {
        switch self {
        case .pendingShares: Icons.share
        case .approvals: Icons.shield
        case .totp: Icons.clock
        case .attention: Icons.alert
        case .recentlyUsed: Icons.orderRepeat
        case .favorites: Icons.star
        case .allItems: Icons.inventory
        case .quickActions: Icons.apps
        }
    }

    /// The full ordered section list for a saved order: recognized saved ids first (in the
    /// saved order, ignoring any unknown/removed id), then sections introduced in code since
    /// the order was saved — appended in canonical `allCases` order so a newly shipped
    /// section is never silently dropped from an existing user's Home.
    static func ordered(savedOrder: [String]) -> [HomeSection] {
        let saved = savedOrder.compactMap(HomeSection.init(rawValue:))
        let missing = allCases.filter { !saved.contains($0) }
        return saved + missing
    }
}

/// Legacy compact horizontal item card, retained in case other feature screens still render
/// it. New Home assembly uses `VaultItemRow` inside grouped cards instead.
struct ItemCard: View {
    let item: VaultItem
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            FaviconView(urlString: item.urlField?.value, category: item.category, size: 36, title: item.title)
            // `appString`, not a bare literal: the ternary makes this the `Text(String)`
            // overload, which renders verbatim and would ship English into VI and JA.
            Text(verbatim: item.title.isEmpty ? appString("Untitled") : item.title)
                .vaultType(.subhead).fontWeight(.medium).lineLimit(1).themedForeground()
            if let sub = item.subtitle, !sub.isEmpty {
                Text(sub).vaultType(.caption).themedForeground(.secondary).lineLimit(1)
            }
        }
        .frame(width: 132, alignment: .leading)
        .padding(Space.s3)
        .background(Color(rgb: theme.elevatedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
