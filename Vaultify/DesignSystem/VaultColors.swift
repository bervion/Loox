import SwiftUI
import UIKit

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

    static let strengthWeak = dynamic(light: 0xD72C0D, dark: 0xFF6B5B)
    static let strengthMedium = dynamic(light: 0xB98900, dark: 0xE3B341)
    static let strengthStrong = dynamic(light: 0x1A8B5E, dark: 0x34C789)

    static func strength(_ strength: PasswordStrength) -> Color {
        switch strength {
        case .weak: return strengthWeak
        case .medium: return strengthMedium
        case .strong: return strengthStrong
        }
    }

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }
}
