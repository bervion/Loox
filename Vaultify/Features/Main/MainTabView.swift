import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The compact (iPhone) unlocked app shell: Home · Items · Watchtower · Search.
///
/// Uses the system `TabView` tab bar for native switching performance and iOS 26 Liquid
/// Glass. Each tab item intentionally provides only a Polaris icon asset, so the visual
/// bar remains icon-only while VoiceOver still gets localized labels. Shared shell
/// behaviors (toast, sheets, auto-lock, section notifications) come from
/// `vaultShellBehaviors()` — the same modifier the iPad/Mac sidebar applies.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(UIStateStore.self) private var uiState

    var body: some View {
        tabContent
            .tint(env.theme.uiTint)
            .vaultShellBehaviors()
    }

    /// Tab list. iOS 18+ uses the `Tab` builder so the Search tab can carry
    /// `role: .search` — that gives the native search experience (on iOS 26 the
    /// search field lives in the tab bar / above the keyboard). iOS 17.6 falls back
    /// to the classic `.tabItem` bar with Search as an ordinary tab.
    @ViewBuilder private var tabContent: some View {
        @Bindable var uiState = uiState
        if #available(iOS 18.0, *) {
            TabView(selection: $uiState.selectedTab) {
                Tab(value: VaultTab.home) { HomeScreen() } label: { tabIcon(.home) }
                Tab(value: VaultTab.items) { ItemsScreen() } label: { tabIcon(.items) }
                Tab(value: VaultTab.watchtower) { WatchtowerScreen() } label: { tabIcon(.watchtower) }
                Tab(value: VaultTab.search, role: .search) { SearchScreen() } label: { tabIcon(.search) }
            }
        } else {
            TabView(selection: $uiState.selectedTab) {
                legacyTab(.home) { HomeScreen() }
                legacyTab(.items) { ItemsScreen() }
                legacyTab(.watchtower) { WatchtowerScreen() }
                legacyTab(.search) { SearchScreen() }
            }
        }
    }

    /// One classic tab (iOS 17.6 fallback): native navigation with an icon-only item.
    private func legacyTab<Content: View>(_ tab: VaultTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .tag(tab)
            .tabItem { tabIcon(tab) }
    }

    @ViewBuilder private func tabIcon(_ tab: VaultTab) -> some View {
        let name = uiState.selectedTab == tab ? tab.iconSelected : tab.icon
        #if canImport(UIKit)
        Image(uiImage: tabImage(name))
            .renderingMode(.template)
            .accessibilityLabel(Text(tab.accessibilityLabel))
        #else
        // macOS sizes the native TabView icon from the SwiftUI Image directly (no
        // intrinsic-size rasterization quirk like iOS's UIKit-backed tab bar).
        Image(name)
            .renderingMode(.template)
            .accessibilityLabel(Text(tab.accessibilityLabel))
        #endif
    }

    #if canImport(UIKit)
    /// The native tab bar sizes a custom template image by its **intrinsic** size and ignores
    /// any SwiftUI `.frame`. The Polaris assets are a 20pt square, so re-render each into a
    /// UIImage at `Metric.iconTab` — the size the bar actually honours (verified: an SF Symbol
    /// renders larger, so the bar sizes by the image, not a fixed slot).
    private func tabImage(_ name: String) -> UIImage {
        let size = CGSize(width: Metric.iconTab, height: Metric.iconTab)
        guard let base = UIImage(named: name) else { return UIImage() }
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.withRenderingMode(.alwaysTemplate)
    }
    #endif

}
