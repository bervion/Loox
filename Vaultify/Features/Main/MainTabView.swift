import SwiftUI
import Combine
import UIKit

/// The unlocked app shell: Home · Items · Watchtower + a dedicated Search tab.
/// On iOS 18+ the Search tab uses `.search` role, which the system renders as a
/// separate trailing circle (Apple News style). Tab titles are hidden so the
/// icons read larger; accessibility labels are kept.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection = 0
    private let inactivityTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    init() { Self.hideTabBarTitles() }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                modernTabs
            } else {
                classicTabs
            }
        }
        .overlay(alignment: .bottom) { copyToast }
        .animation(.spring(duration: 0.3), value: env.clipboard.recentCopyLabel)
        .onChange(of: selection) { _, _ in env.session.registerActivity() }
        .onReceive(inactivityTimer) { _ in env.session.lockIfTimedOut() }
    }

    @available(iOS 18.0, *)
    private var modernTabs: some View {
        TabView(selection: $selection) {
            Tab("Home", image: selection == 0 ? Icons.homeFill : Icons.home, value: 0) { HomeScreen() }
            Tab("Items", image: selection == 1 ? Icons.organizationFill : Icons.organization, value: 1) { ItemsScreen() }
            Tab("Watchtower", image: selection == 2 ? Icons.planFill : Icons.plan, value: 2) { WatchtowerScreen() }
            Tab("Search", image: Icons.search, value: 3, role: .search) { SearchScreen() }
        }
    }

    private var classicTabs: some View {
        TabView(selection: $selection) {
            HomeScreen().tag(0)
                .tabItem { Label("Home", image: selection == 0 ? Icons.homeFill : Icons.home) }
            ItemsScreen().tag(1)
                .tabItem { Label("Items", image: selection == 1 ? Icons.organizationFill : Icons.organization) }
            WatchtowerScreen().tag(2)
                .tabItem { Label("Watchtower", image: selection == 2 ? Icons.planFill : Icons.plan) }
            SearchScreen().tag(3)
                .tabItem { Label("Search", image: Icons.search) }
        }
    }

    @ViewBuilder private var copyToast: some View {
        if let label = env.clipboard.recentCopyLabel {
            HStack(spacing: 8) {
                PolarisIcon(Icons.checkCircle, size: 18).foregroundStyle(VaultColors.strengthStrong)
                Text("Copied \(label)").font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
            .padding(.bottom, 70)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Hide tab-item titles (icon-only bar) while keeping the icons' accessibility
    /// labels. Pushes the title off-screen and clears its color across layouts.
    private static func hideTabBarTitles() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        let off = UIOffset(horizontal: 0, vertical: 200)
        let clear: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.clear]
        for layout in [appearance.stackedLayoutAppearance,
                       appearance.inlineLayoutAppearance,
                       appearance.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = clear
            layout.selected.titleTextAttributes = clear
            layout.normal.titlePositionAdjustment = off
            layout.selected.titlePositionAdjustment = off
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
