import SwiftUI

/// "Readable password" per-character coloring: digits in the login-category blue,
/// symbols in the destructive red, letters in the primary color. Shared by the
/// Large Type viewer and the generator output so the scheme stays identical.
enum SecretColoring {
    /// Reading color for a single character: digit → login blue, letter → primary,
    /// symbol → destructive red.
    static func color(for character: Character, theme: AppTheme) -> Color {
        if character.isNumber { return VaultColors.category(.login) }
        if character.isLetter { return theme.color(.primary) }
        return theme.color(.destructive)
    }

    static func attributed(_ text: String, theme: AppTheme) -> AttributedString {
        var result = AttributedString()
        for character in text {
            var piece = AttributedString(String(character))
            piece.foregroundColor = color(for: character, theme: theme)
            result.append(piece)
        }
        return result
    }
}
