import SwiftUI

/// Synchronously-readable snapshot of the active theme, for static color accessors
/// (e.g. `VaultColors`) that have no SwiftUI view context. Updated by `ThemeStore`
/// whenever the active theme changes; views re-read it on the re-render that the
/// theme change triggers (tint / colorScheme / appTheme environment all change).
@MainActor enum ThemeHolder {
    static var current: AppTheme = BuiltinThemes.day
}
