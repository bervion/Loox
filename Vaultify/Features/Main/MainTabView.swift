import SwiftUI
import Combine

/// The unlocked app shell: four native tabs with Polaris tab icons, a transient
/// copy confirmation, and a foreground inactivity auto-lock check. Search is the
/// native `.searchable` bar on the Vault tab (not a separate tab).
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selection = 0
    private let inactivityTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView(selection: $selection) {
            HomeScreen()
                .tag(0)
                .tabItem { Label("Home", image: selection == 0 ? Icons.homeFill : Icons.home) }
            ItemsScreen()
                .tag(1)
                .tabItem { Label("Items", image: selection == 1 ? Icons.organizationFill : Icons.organization) }
            WatchtowerScreen()
                .tag(2)
                .tabItem { Label("Watchtower", image: selection == 2 ? Icons.planFill : Icons.plan) }
            SearchScreen()
                .tag(3)
                .tabItem { Label("Search", image: Icons.search) }
        }
        .overlay(alignment: .bottom) { copyToast }
        .animation(.spring(duration: 0.3), value: env.clipboard.recentCopyLabel)
        .onChange(of: selection) { _, _ in env.session.registerActivity() }
        .onReceive(inactivityTimer) { _ in env.session.lockIfTimedOut() }
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
