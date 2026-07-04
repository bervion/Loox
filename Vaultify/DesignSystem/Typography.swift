import SwiftUI

extension Font {
    /// MonoLisa — the monospaced typeface for secrets, codes, card numbers, TOTP,
    /// and detail field values. Scales with Dynamic Type via `relativeTo:`. Only
    /// Regular + Bold faces are bundled, so `.semibold`+ maps to Bold, else Regular
    /// (MonoLisa is monospaced, so digits already align without `.monospacedDigit()`).
    static func vaultCode(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .custom(vaultCodeFaceName(weight), size: vaultCodeBaseSize(style), relativeTo: style)
    }

    /// MonoLisa at an explicit (already Dynamic-Type-scaled) point size — for
    /// callers that drive the size themselves (e.g. `@ScaledMetric`).
    static func vaultCode(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(vaultCodeFaceName(weight), size: size)
    }
}

private func vaultCodeFaceName(_ weight: Font.Weight) -> String {
    let bold = weight == .semibold || weight == .bold || weight == .heavy || weight == .black
    return bold ? "MonoLisa-Bold" : "MonoLisa-Regular"
}

/// Apple's default point sizes per text style, used as the MonoLisa base size that
/// `relativeTo:` then scales with the user's text-size setting.
private func vaultCodeBaseSize(_ style: Font.TextStyle) -> CGFloat {
    switch style {
    case .largeTitle:  return 34
    case .title:       return 28
    case .title2:      return 22
    case .title3:      return 20
    case .headline:    return 17
    case .body:        return 17
    case .callout:     return 16
    case .subheadline: return 15
    case .footnote:    return 13
    case .caption:     return 12
    case .caption2:    return 11
    @unknown default:  return 17
    }
}

/// Typography roles from the Vaultify Design System hierarchy (large title 34 ·
/// screen 22 · section 19 · body 17 · callout 16 · subhead 15 · footnote 13 ·
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
        case .screenTitle:  return .system(.title2).weight(.bold)
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
