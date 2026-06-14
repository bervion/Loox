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

    // The search tab MUST be declared with only `value:` + `role: .search` (no
    // title/image) — passing a title or image keeps it inline. With that, iOS 26
    // detaches it into its own floating Liquid-Glass search button and drops its
    // `.searchable` field to the bottom (Apple News pattern). `selection`/`value`
    // on the regular tabs is fine and keeps the filled-on-select icon swap.
    // `SearchScreen` owns the NavigationStack + `.searchable`.
    @available(iOS 18.0, *)
    private var modernTabs: some View {
        TabView(selection: $selection) {
            Tab("Home", image: selection == 0 ? Icons.homeFill : Icons.home, value: 0) { HomeScreen() }
            Tab("Items", image: selection == 1 ? Icons.organizationFill : Icons.organization, value: 1) { ItemsScreen() }
            Tab("Watchtower", image: selection == 2 ? Icons.planFill : Icons.plan, value: 2) { WatchtowerScreen() }
            Tab(value: 3, role: .search) { SearchScreen() }
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
