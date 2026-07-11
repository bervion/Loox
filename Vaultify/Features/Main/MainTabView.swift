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
        shell
            .tint(env.theme.uiTint)
            .vaultShellBehaviors()
    }

    /// iOS 26+ keeps the native Liquid Glass bar. Pre-26 the native bar renders
    /// transparent at the scroll edge (bare icons on the canvas), so those
    /// shells hide it per tab (`tabRoot`) and mount the floating chip bar as a
    /// bottom safe-area inset — scroll views then clear it automatically.
    @ViewBuilder private var shell: some View {
        @Bindable var uiState = uiState
        if #available(iOS 26.0, *) {
            tabContent
        } else {
            tabContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    LegacyChipTabBar(selection: $uiState.selectedTab)
                }
        }
    }

    /// Wraps one tab's root content; pre-26 it hides the native tab bar (the
    /// chip bar replaces it).
    @ViewBuilder private func tabRoot<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content()
        } else {
            content().toolbar(.hidden, for: .tabBar)
        }
        #else
        content()
        #endif
    }

    /// Tab list. iOS 18+ uses the `Tab` builder so the Search tab can carry
    /// `role: .search` — that gives the native search experience (on iOS 26 the
    /// search field lives in the tab bar / above the keyboard). iOS 17.6 falls back
    /// to the classic `.tabItem` bar with Search as an ordinary tab.
    @ViewBuilder private var tabContent: some View {
        @Bindable var uiState = uiState
        if #available(iOS 18.0, *) {
            TabView(selection: $uiState.selectedTab) {
                Tab(value: VaultTab.home) { tabRoot { HomeScreen() } } label: { tabIcon(.home) }
                Tab(value: VaultTab.items) { tabRoot { ItemsScreen() } } label: { tabIcon(.items) }
                Tab(value: VaultTab.watchtower) { tabRoot { WatchtowerScreen() } } label: { tabIcon(.watchtower) }
                Tab(value: VaultTab.search, role: .search) { tabRoot { SearchScreen() } } label: { tabIcon(.search) }
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
        tabRoot(content)
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
