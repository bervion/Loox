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
        TabView(selection: $selection) {
            tab(.home) { HomeScreen() }
            tab(.items) { ItemsScreen() }
            tab(.watchtower) { WatchtowerScreen() }
            tab(.search) { SearchScreen() }
        }
        .tint(Color(rgb: env.theme.active.accent))
        .overlay(alignment: .bottom) { copyToast }
        .animation(.spring(duration: 0.3), value: env.clipboard.recentCopyLabel)
        .onChange(of: selection) { _, _ in
            env.session.registerActivity()
        }
        .onReceive(inactivityTimer) { _ in env.session.lockIfTimedOut() }
        .onAppear { env.theme.morphMesh() }
    }

    /// One tab: native system navigation with an icon-only tab item.
    private func tab<Content: View>(_ tab: VaultTab, @ViewBuilder content: () -> Content) -> some View {
        content()
            .tag(tab)
            .tabItem { tabIcon(tab) }
    }

    @ViewBuilder private func tabIcon(_ tab: VaultTab) -> some View {
        Image(selection == tab ? tab.iconSelected : tab.icon)
            .renderingMode(.template)
            .accessibilityLabel(Text(tab.accessibilityLabel))
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
