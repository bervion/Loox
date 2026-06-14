import SwiftUI
import Combine

/// The unlocked app shell: Home · Items · Watchtower + a dedicated Search tab.
/// On iOS 18+ the Search tab uses `.search` role, which the system renders as a
/// separate trailing search button (Apple News style on iOS 26 Liquid Glass).
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection = 0
    private let inactivityTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

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

    // No `selection`/`value:` here on purpose: programmatic selection keeps the
    // search role inline. Without it, `Tab(role: .search)` detaches into its own
    // floating Liquid-Glass search button and its `.searchable` field drops to the
    // bottom (Apple News pattern). The system tints the active tab, so outline
    // icons are fine. `SearchScreen` owns the NavigationStack + `.searchable`.
    @available(iOS 18.0, *)
    private var modernTabs: some View {
        TabView {
            Tab("Home", image: Icons.home) { HomeScreen() }
            Tab("Items", image: Icons.organization) { ItemsScreen() }
            Tab("Watchtower", image: Icons.plan) { WatchtowerScreen() }
            Tab(role: .search) { SearchScreen() }
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
}
