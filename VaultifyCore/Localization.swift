import Foundation

/// The locale used to resolve `LocalizedStringResource` titles (field types,
/// item categories, settings enums) so they follow the in-app Language choice
/// rather than the device language. `SettingsStore` keeps it current at launch
/// and whenever the language changes. Read/written on the main actor only.
///
/// Lives in VaultifyCore so both the app and the AutoFill extension resolve
/// shared model titles against the same locale.
nonisolated(unsafe) var appResourceLocale: Locale = .autoupdatingCurrent

/// Map a stored language code ("system" | "en" | "vi") to a `Locale`.
nonisolated func appLocale(forCode code: String) -> Locale {
    switch code {
    case "en": return Locale(identifier: "en")
    case "vi": return Locale(identifier: "vi")
    default: return .autoupdatingCurrent
    }
}

extension LocalizedStringResource {
    /// The same resource pinned to the in-app language, so SwiftUI and
    /// `String(localized:)` resolve it against the user's chosen locale.
    nonisolated var inAppLocalized: LocalizedStringResource {
        var copy = self
        copy.locale = appResourceLocale
        return copy
    }
}

/// Resolve a literal UI string against the in-app language rather than the
/// device locale. Use for runtime strings (errors, prompts) built outside SwiftUI.
nonisolated func appString(_ key: String.LocalizationValue) -> String {
    String(localized: key, locale: appResourceLocale)
}
