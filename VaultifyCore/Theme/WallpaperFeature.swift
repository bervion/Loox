import Foundation

/// Master switch for decorative wallpapers (gradient / pattern / animated mesh / photo).
///
/// Disabled = flat themed backgrounds everywhere — the simplified Design-System look
/// (`Design System/tokens/colors.css`: "No decorative gradients as primary language").
/// The wallpaper engine code is fully retained; flip this to `true` to re-enable the
/// advanced (Telegram-style) theming surface later.
nonisolated enum WallpaperFeature {
    static let decorativeEnabled = false
}
