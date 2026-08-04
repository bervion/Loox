import SwiftUI

/// Which unlocked shell the app runs, decided purely from the two size classes.
///
/// Kept separate from the view so the whole matrix is testable: a regression here is
/// invisible in code review (it looks like one comparison) but rewrites navigation for
/// an entire device class.
nonisolated enum AdaptiveShell {

    enum Layout: Equatable {
        /// UIKit navigation shell: `MainTabView` (native search + Liquid Glass tab bar)
        /// hosted in a `UINavigationController` so detail pushes cover the tab bar with a
        /// native full-screen slide. See `VaultUINavShell`.
        case tabs
        /// `NavigationSplitView` with a pinned sidebar; pushes happen inside the detail
        /// column and there is no tab bar.
        case sidebar
    }

    /// The sidebar shell requires **both** axes regular.
    ///
    /// Horizontal alone is not enough: a Plus/Max-class iPhone in landscape reports
    /// regular horizontal with compact vertical, and giving it the sidebar would drop the
    /// tab bar, spend 200-320pt of an already short screen on a pinned sidebar, and swap
    /// every push from a full-screen UIKit slide to an in-column SwiftUI push — all from
    /// an ordinary rotation. Only a genuinely large canvas (iPad full screen or a wide
    /// split) reports regular on both axes.
    ///
    /// A `nil` size class (reported before the first layout pass) resolves to `.tabs`,
    /// which is the correct default for the phone-shaped canvas and avoids a one-frame
    /// sidebar flash.
    static func layout(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?
    ) -> Layout {
        horizontal == .regular && vertical == .regular ? .sidebar : .tabs
    }
}

/// Chooses the unlocked shell layout from the size classes: the bottom-tab `MainTabView`
/// on anything phone-shaped (including a large iPhone in landscape, which reports regular
/// width) and the `NavigationSplitView` sidebar only on a canvas that is regular on both
/// axes (iPad full-screen, wide split view).
///
/// Both branches share the same underlying screens and `UIStateStore`, so a size-class
/// flip (Stage Manager, rotation, split-view resize) carries selection over via the live
/// `sidebarSelection`/`selectedTab` model rather than a one-shot restore.
struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        #if os(macOS)
        // The Mac gets its own three-column shell (sidebar · list · detail) with
        // toolbar search — no Home or Search screens on this platform.
        MacRootView()
        #else
        switch AdaptiveShell.layout(horizontal: horizontalSizeClass, vertical: verticalSizeClass) {
        case .tabs:
            VaultUINavShell(env: env)
                .ignoresSafeArea()
        case .sidebar:
            VaultSidebarView()
        }
        #endif
    }
}
