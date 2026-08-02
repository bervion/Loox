import Foundation

/// Pure decision of HOW a field value renders on the detail screen.
///
/// Secret policy is evaluated BEFORE presentation kind: a `protected` value can
/// never reach a rich-text renderer (Markdown) or any other plaintext-first
/// branch, regardless of its `FieldKind`. The detail row switches on this
/// result instead of on `FieldKind` directly, so the masking promise is a
/// testable contract rather than an accident of branch order.
nonisolated enum DetailValuePresentation: Equatable, Sendable {
    /// Live TOTP code with countdown ring.
    case totpCode
    /// Tappable colored URL.
    case url
    /// Markdown-rendered note. Only reachable for non-secret multiline values.
    case markdownNote
    /// Grouped card number with brand badge (secret-masked glyphs).
    case cardNumber
    /// Single-line secret rendered through masked glyph resolution.
    case secretGlyphs
    /// Multiline secret: fixed mask until an explicit reveal; revealed content
    /// renders as plain selectable monospace, never through Markdown.
    case protectedMultiline
    /// Ordinary plain text.
    case plainText

    /// - Parameters:
    ///   - kind: the field's presentation kind.
    ///   - isProtected: `DynamicField.protected` — display masking policy.
    ///   - isCardNumber: whether this is the card template's number field.
    static func resolve(kind: FieldKind, isProtected: Bool, isCardNumber: Bool) -> DetailValuePresentation {
        // Secret policy first: a protected multiline value (SSH private key,
        // recovery codes) must never initialize the Markdown renderer.
        if kind.isMultiline {
            return (isProtected || kind.isSecret) ? .protectedMultiline : .markdownNote
        }
        switch kind {
        case .totp: return .totpCode
        case .url: return .url
        case .monospace where isCardNumber: return .cardNumber
        default:
            return (isProtected || kind.isSecret) ? .secretGlyphs : .plainText
        }
    }
}
