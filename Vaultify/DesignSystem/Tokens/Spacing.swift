import CoreGraphics

/// 4pt spacing grid + screen gutter from the Vaultify Design System
/// (`Design System/tokens/spacing.css`). Use a token instead of a hardcoded number so
/// spacing stays consistent and tunable app-wide.
nonisolated enum Space {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s7: CGFloat = 32
    static let s8: CGFloat = 40
    static let s9: CGFloat = 48
    static let s10: CGFloat = 64

    /// Default screen horizontal gutter.
    static let gutter: CGFloat = 16
    /// Max readable content width (iPhone portrait).
    static let contentMax: CGFloat = 430
}
