import SwiftUI
import Foundation

/// Semantic colors adapted from the Polaris palette, resolved per light/dark
/// trait at render time so they track the system appearance.
enum VaultColors {
    static func category(_ category: ItemCategory) -> Color {
        switch category {
        case .login: return dynamic(light: 0x2C6ECB, dark: 0x5B9CF6)
        case .note: return dynamic(light: 0xB98900, dark: 0xE3B341)
        case .card: return dynamic(light: 0x1A8B5E, dark: 0x34C789)
        case .identity: return dynamic(light: 0x9C6ADE, dark: 0xBD93F9)
        case .sshKey: return dynamic(light: 0x00A0AC, dark: 0x26C9D3)
        case .recoveryCodes: return dynamic(light: 0xC4571E, dark: 0xF08A4B)
        case .securityQuestions: return dynamic(light: 0x5B5BD6, dark: 0x9B9BF0)
        case .custom: return dynamic(light: 0x6D7175, dark: 0x9BA1A6)
        }
    }

    /// Copy-flash confirmation: the brand blue (the capsule-CTA hue) with white
    /// content. Deliberately NOT the theme accent — mono/graphite accents
    /// resolve to pale fills whose WCAG on-color is near-black, which made the
    /// flash read as a murky wash with black text.
    static let copyFlash = dynamic(light: 0x0065F4, dark: 0x0065F4)
    static let copyFlashText = Color.white

    static let strengthWeak = dynamic(light: 0xD72C0D, dark: 0xFF6B5B)
    static let strengthMedium = dynamic(light: 0xB98900, dark: 0xE3B341)
    static let strengthStrong = dynamic(light: 0x1A8B5E, dark: 0x34C789)
    /// Favorite-star gold — brighter than the amber strength color; shared by the item rows
    /// and the detail header so the star reads the same everywhere.
    static let favoriteStar = Color(red: 1.0, green: 0.78, blue: 0.13)

    /// Colour for a graded estimate. The five grades collapse onto the three strength colours
    /// on purpose: the ring's FILL already carries the finer distinction, so giving `fair` and
    /// `strong` their own hues would say the same thing twice and dilute red-means-fix-this.
    static func strength(grade: PasswordGrade) -> Color {
        switch grade {
        case .veryWeak, .weak: return strengthWeak
        case .fair: return strengthMedium
        case .strong, .excellent: return strengthStrong
        }
    }

    static func strength(_ strength: PasswordStrength) -> Color {
        switch strength {
        case .weak: return strengthWeak
        case .medium: return strengthMedium
        case .strong: return strengthStrong
        }
    }

    // Theme-driven surfaces. Resolved through a *dynamic* platform color so SwiftUI re-resolves
    // them whenever the color scheme flips (day↔night) — keeping these backgrounds in
    // lock-step with trait-driven foregrounds (.primary/.secondary) instead of lagging a
    // frame behind a static snapshot (which left text mismatched until an app restart).
    // The provider reads the live active theme, so tinted / custom themes apply too.
    /// The true accent (blue in both modes). Use for toggles / fills that must stay accent
    /// even though the global control tint goes white in dark mode.
    static var accent: Color { themed(\.accent) }
    static var surface: Color { themed(\.elevatedBackground) }
    static var groupedBackground: Color { themed(\.groupedBackground) }
    static var fill: Color { themed(\.controlBackground) }
    static var separatorColor: Color { themed(\.separator) }

    private static func themed(_ key: KeyPath<AppTheme, UInt32>) -> Color {
        // The theme value doesn't depend on light/dark — `platformThemed` re-evaluates
        // on appearance change (and app re-renders on theme mutation), which is all
        // this needs to stay live.
        Color.platformThemed { _ in ThemeHolder.current[keyPath: key] }
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color.platformDynamic(light: light, dark: dark)
    }
}
