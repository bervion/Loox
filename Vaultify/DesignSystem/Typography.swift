import SwiftUI

extension Font {
    /// Monospaced font for secrets, codes, card numbers, and TOTP — clean
    /// vertical alignment, the native SF Mono (the "Apple default" mono face).
    static func vaultMono(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

extension View {
    /// Hide the receiver's contents when the app is backgrounded (privacy
    /// screen / app-switcher snapshot protection).
    func privacySensitiveContents(_ active: Bool = true) -> some View {
        privacySensitive(active)
    }
}
