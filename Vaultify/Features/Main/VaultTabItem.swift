import SwiftUI

/// The four shell tabs. Owns outline + filled Polaris icon assets, a localized
/// VoiceOver label (the bar shows NO text — icon-only by design), and stable order.
enum VaultTab: Int, CaseIterable, Identifiable {
    case home, items, watchtower, search
    var id: Int { rawValue }

    /// Inactive (outline) icon.
    var icon: String {
        switch self {
        case .home: return Icons.home
        case .items: return Icons.apps
        case .watchtower: return Icons.organization
        case .search: return Icons.search
        }
    }

    /// Active (filled) icon. Polaris ships filled variants for all but search.
    var iconSelected: String {
        switch self {
        case .home: return Icons.homeFill
        case .items: return Icons.appsFill
        case .watchtower: return Icons.organizationFill
        case .search: return Icons.search
        }
    }

    /// Localized accessibility label, resolved against the in-app language. Not shown
    /// visually — exposed to VoiceOver only.
    var accessibilityLabel: LocalizedStringResource {
        switch self {
        case .home: return LocalizedStringResource("Home").inAppLocalized
        case .items: return LocalizedStringResource("Items").inAppLocalized
        case .watchtower: return LocalizedStringResource("Watchtower").inAppLocalized
        case .search: return LocalizedStringResource("Search").inAppLocalized
        }
    }
}
