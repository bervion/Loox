import SwiftUI
import Combine

/// The unlocked app shell: Home · Items · Watchtower · Search.
///
/// Uses the system `TabView` tab bar for native switching performance and iOS 26 Liquid
/// Glass. Each tab item intentionally provides only a Polaris icon asset, so the visual
/// bar remains icon-only while VoiceOver still gets localized labels.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection: VaultTab = .home
    private let inactivityTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    /// Keeps transient toasts above the native tab bar without depending on custom bar metrics.
    private var tabBarToastClearance: CGFloat { Metric.controlLarge + Space.s8 }

    var body: some View {
        tabContent
            .tint(Color(rgb: env.theme.active.accent))
            .overlay(alignment: .bottom) { copyToast }
            .animation(.spring(duration: 0.3), value: env.clipboard.recentCopyLabel)
            .onChange(of: selection) { _, _ in
                env.session.registerActivity()
            }
            .onReceive(inactivityTimer) { _ in env.session.lockIfTimedOut() }
            .onAppear { env.theme.morphMesh() }
            .onReceive(NotificationCenter.default.publisher(for: .vaultSwitchToSearch)) { _ in
                selection = .search
            }
            .onReceive(NotificationCenter.default.publisher(for: .vaultSwitchToWatchtower)) { _ in
                selection = .watchtower
            }
            .onReceive(NotificationCenter.default.publisher(for: .vaultSwitchToItems)) { _ in
                selection = .items
            }
    }

    /// Tab list. iOS 18+ uses the `Tab` builder so the Search tab can carry
    /// `role: .search` — that gives the native search experience (on iOS 26 the
    /// search field lives in the tab bar / above the keyboard). iOS 17.6 falls back
    /// to the classic `.tabItem` bar with Search as an ordinary tab.
    @ViewBuilder private var tabContent: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selection) {
                Tab(value: VaultTab.home) { HomeScreen() } label: { tabIcon(.home) }
                Tab(value: VaultTab.items) { ItemsScreen() } label: { tabIcon(.items) }
                Tab(value: VaultTab.watchtower) { WatchtowerScreen() } label: { tabIcon(.watchtower) }
                Tab(value: VaultTab.search, role: .search) { SearchScreen() } label: { tabIcon(.search) }
            }
        } else {
            TabView(selection: $selection) {
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
        Image(uiImage: tabImage(selection == tab ? tab.iconSelected : tab.icon))
            .renderingMode(.template)
            .accessibilityLabel(Text(tab.accessibilityLabel))
    }

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

    @ViewBuilder private var copyToast: some View {
        if let label = env.clipboard.recentCopyLabel {
            HStack(spacing: Space.s2) {
                PolarisIcon(Icons.checkCircle, size: Metric.iconInline)
                    .foregroundStyle(Color(rgb: env.theme.active.success))
                Text(appString("Copied \(label)")).vaultType(.subhead).fontWeight(.medium)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .background(.regularMaterial, in: Capsule())
            .elevation(.level2)
            .padding(.bottom, tabBarToastClearance)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
