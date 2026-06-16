import SwiftUI

extension Font {
    /// Monospaced font for secrets, codes, card numbers, and TOTP — clean
    /// vertical alignment, the native SF Mono (the "Apple default" mono face).
    static func vaultMono(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

/// Typography roles from the Vaultify Design System hierarchy (large title 34 ·
/// screen 28 · section 19 · body 17 · callout 16 · subhead 15 · footnote 13 ·
/// caption 12), mapped onto Apple Dynamic Type text styles so they scale with the
/// user's text-size setting and stay Apple-native. Use a role via `.vaultType(_:)`,
/// never an ad-hoc `.font(.system(size:))`.
nonisolated enum VaultType {
    case largeTitle    // rare root identity screens
    case screenTitle   // root screen title ("Kho")
    case section       // section heading
    case headline      // emphasized row title
    case body          // main content
    case callout       // secondary row content
    case subhead       // supporting text
    case footnote      // metadata
    case caption       // smallest metadata
    case sectionLabel  // short ALL-CAPS group header

    var font: Font {
        switch self {
        case .largeTitle:   return .system(.largeTitle).weight(.bold)
        case .screenTitle:  return .system(.title).weight(.bold)
        case .section:      return .system(.title3).weight(.semibold)
        case .headline:     return .system(.headline)
        case .body:         return .system(.body)
        case .callout:      return .system(.callout)
        case .subhead:      return .system(.subheadline)
        case .footnote:     return .system(.footnote)
        case .caption:      return .system(.caption)
        case .sectionLabel: return .system(.footnote).weight(.semibold)
        }
    }
}

extension View {
    /// Apply a Design-System typography role.
    func vaultType(_ role: VaultType) -> some View { font(role.font) }
}

extension Text {
    /// Apply a Design-System typography role to `Text` (chainable before styling).
    func vaultType(_ role: VaultType) -> Text { font(role.font) }
}

extension View {
    /// Hide the receiver's contents when the app is backgrounded (privacy
    /// screen / app-switcher snapshot protection).
    func privacySensitiveContents(_ active: Bool = true) -> some View {
        privacySensitive(active)
    }
}
