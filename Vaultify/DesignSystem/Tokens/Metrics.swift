import CoreGraphics

/// Control + element sizing tokens (Design System `tokens/spacing.css`): control
/// heights, minimum hit target, list row height, and icon optical sizes.
nonisolated enum Metric {
    /// Minimum touch target (Apple HIG / WCAG).
    static let hitMin: CGFloat = 44

    // Control heights
    static let controlSmall: CGFloat = 34
    static let controlMedium: CGFloat = 44
    static let controlLarge: CGFloat = 52

    /// Standard list row height.
    static let rowHeight: CGFloat = 56

    // Icon optical sizes
    static let iconInline: CGFloat = 20    // inline within text / rows
    static let iconUtility: CGFloat = 24   // utility tiles / toolbar
    static let iconTab: CGFloat = 28       // tab bar (icon-only → standard tab-icon size)
    static let iconTile: CGFloat = 32      // leading row tile
    static let iconTileLarge: CGFloat = 40
}

/// Floating icon-only tab bar layout (Design System: Threads-style minimal bar).
nonisolated enum TabBarMetric {
    static let horizontalInset: CGFloat = 22   // bar inset from screen edges
    static let bottomOffset: CGFloat = 12      // above the safe area
    static let height: CGFloat = 62
    static var cornerRadius: CGFloat { height / 2 }
    static let indicatorSize: CGFloat = 46     // selected pill behind the icon
    static let badgeDot: CGFloat = 8
    /// Bottom padding scrollable content must reserve so the bar never covers rows.
    static let contentBottomInset: CGFloat = 110
}
