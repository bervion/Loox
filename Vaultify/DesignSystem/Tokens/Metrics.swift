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
    /// Compact icon tier for inline banner/chip glyphs (`VaultInfoBanner`, `CapabilityBannerView`,
    /// `FilterChip`) — smaller than `iconInline` since these sit beside footnote/subhead text,
    /// not body rows.
    static let iconCompact: CGFloat = 16
    static let iconInline: CGFloat = 20    // inline within text / rows
    static let iconUtility: CGFloat = 24   // utility tiles / toolbar
    static let iconTab: CGFloat = 28       // tab bar (icon-only → standard tab-icon size)
    static let iconTile: CGFloat = 32      // leading row tile
    static let iconTileLarge: CGFloat = 40

    /// Row-leading folder/Space badge tile (`FolderBadge`, `ItemsScreen`/`FolderPickerSheet`
    /// row leading tiles, "None" placeholder tile) — distinct from `iconTile` (32) since this
    /// size recurs specifically for the folder badge family.
    static let badgeTile: CGFloat = 30
    /// Icon-picker grid tile (`IconColorPicker`'s curated-icon grid cell).
    static let iconPickerTile: CGFloat = 50
}

/// Floating icon-only tab bar layout (Design System: Threads-style minimal bar).
nonisolated enum TabBarMetric {
    static let horizontalInset: CGFloat = 22   // bar inset from screen edges
    static let bottomOffset: CGFloat = 12      // above the safe area
    static let height: CGFloat = 62
    static var cornerRadius: CGFloat { height / 2 }
    static let indicatorSize: CGFloat = 46     // selected pill behind the icon
    static let badgeDot: CGFloat = 8
    /// Bottom breathing space below the last row. The native `TabView` bar already reserves
    /// its own safe-area inset, so this is just a small margin — not the full bar height
    /// (the old floating-overlay bar needed ~110; the system bar does not).
    static let contentBottomInset: CGFloat = 24
}
