import SwiftUI

/// Chooses the unlocked shell layout by horizontal size class: the bottom-tab
/// `MainTabView` on compact width (iPhone, narrow iPad multitasking) and the
/// `NavigationSplitView` sidebar on regular width (iPad full-screen, Mac).
///
/// Both branches share the same underlying screens and `UIStateStore`, so a size-class
/// flip (Stage Manager, rotation, split-view resize) carries selection over via the live
/// `sidebarSelection`/`selectedTab` model rather than a one-shot restore.
struct AdaptiveRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        #if os(macOS)
        // The Mac gets its own three-column shell (sidebar · list · detail) with
        // toolbar search — no Home or Search screens on this platform.
        MacRootView()
        #else
        if horizontalSizeClass == .compact {
            MainTabView()
        } else {
            VaultSidebarView()
        }
        #endif
    }
}
