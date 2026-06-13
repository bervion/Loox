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
            VaultListScreen()
                .tag(0)
                .tabItem { Label("Vault", image: selection == 0 ? Icons.homeFill : Icons.home) }
            GeneratorScreen()
                .tag(1)
                .tabItem { Label("Generator", image: Icons.magic) }
            WatchtowerScreen()
                .tag(2)
                .tabItem { Label("Watchtower", image: Icons.shield) }
            SettingsScreen()
                .tag(3)
                .tabItem { Label("Settings", image: selection == 3 ? Icons.settingsFill : Icons.settings) }
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
