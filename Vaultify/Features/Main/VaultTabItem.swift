import SwiftUI

/// The four shell tabs. Owns outline + filled icon tokens, a localized
/// VoiceOver label (the bar shows NO text — icon-only by design), and stable order.
enum VaultTab: Int, CaseIterable, Identifiable {
    case home, items, watchtower, search
    var id: Int { rawValue }

    /// Inactive (outline) icon.
    var icon: String {
        switch self {
        case .home: return Icons.home
        case .items: return Icons.apps
        case .watchtower: return Icons.securityTab
        case .search: return Icons.search
        }
    }

    /// Active (filled) icon. Every tab has a filled sibling except search, whose
    /// magnifying glass has none.
    var iconSelected: String {
        switch self {
        case .home: return Icons.homeFill
        case .items: return Icons.appsFill
        case .watchtower: return Icons.securityTabFill
        case .search: return Icons.search
        }
    }

    /// Localized accessibility label, resolved against the in-app language. Not shown
    /// visually — exposed to VoiceOver only.
    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .home: return LocalizedStringResource("Home").inAppLocalized
        case .items: return LocalizedStringResource("Items").inAppLocalized
        case .watchtower: return LocalizedStringResource("Security").inAppLocalized
        case .search: return LocalizedStringResource("Search").inAppLocalized
        }
    }
}
