import SwiftUI

extension Font {
    /// Apple's system font for secrets, codes, card numbers and detail field values.
    ///
    /// The app ships no third-party typeface: this is SF, so it inherits Dynamic Type, every
    /// weight, and the full glyph coverage of the system font for free. Digits are TABULAR —
    /// a code that ticks over, a card number that reveals, or a value that resolves glyph by
    /// glyph must not shift width as its digits change. Letters keep SF's proportional
    /// advances, which is what makes a secret read as text rather than as a terminal dump.
    static func vaultCode(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(style, weight: weight).monospacedDigit()
    }

    /// The same face at an explicit (already Dynamic-Type-scaled) point size — for callers
    /// that drive the size themselves (e.g. `@ScaledMetric`).
    static func vaultCode(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// Magazine display face for full-bleed cinematic surfaces (story intro
    /// hero titles; future hero pages) — SF at its heaviest weight, ABOVE the
    /// `largeTitle` role, which caps at 34 and at `.bold`. Like
    /// `vaultCode(size:)`, the caller drives the size and keeps Dynamic Type by
    /// deriving it via `@ScaledMetric(relativeTo: .largeTitle)`. Not for chrome
    /// or content screens: those stay on the `VaultType` role ladder.
    ///
    /// `.black` rather than a licensed display face on purpose: the app bundles
    /// no third-party typeface, and SF Pro Black covers Latin and full
    /// Vietnamese diacritic stacking in one call. Japanese falls back to
    /// Hiragino Sans, which ships no Black — JA titles land around W6, so the
    /// hero weight is deliberately lighter there rather than synthesised.
    static func vaultDisplay(size: CGFloat) -> Font {
        .system(size: size, weight: .black)
    }
}

/// Typography roles from the Vaultify Design System hierarchy (large title 34 ·
/// screen 22 · section 19 · body 17 · callout 16 · subhead 15 · footnote 13 ·
/// caption 12), mapped onto Apple Dynamic Type text styles so they scale with the
/// user's text-size setting and stay Apple-native. Use a role via `.vaultType(_:)`,
/// never an ad-hoc `.font(.system(size:))`.
nonisolated enum VaultType {
    /// The Watchtower gauge's score figure — the one display-size number in the
    /// app. Fixed size on purpose: it lives inside the dial's fixed 260pt canvas
    /// geometry, which does not scale with Dynamic Type either; the accessible
    /// reading is the gauge's accessibility label, not a scaled glyph.
    case scoreDisplay
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
        case .scoreDisplay: return .system(size: 58, weight: .bold)
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
