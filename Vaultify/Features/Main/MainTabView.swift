import SwiftUI
import Combine

/// The unlocked app shell: Home · Items · Watchtower · Search.
///
/// Uses the system `TabView` tab bar for native switching performance and iOS 26 Liquid
/// Glass. Each tab item intentionally provides only a Polaris icon asset, so the visual
/// bar remains icon-only while VoiceOver still gets localized labels.
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(UIStateStore.self) private var uiState
    @Environment(\.scenePhase) private var scenePhase
    @State private var shakeDetector = ShakeToLockService()
    private let inactivityTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var uiState = uiState
        return tabContent
            .tint(env.theme.uiTint)
            .overlay(alignment: .bottom) { CopyToastOverlay() }
            .animation(.spring(duration: 0.3), value: env.clipboard.recentCopyLabel)
            .onChange(of: uiState.selectedTab) { _, _ in
                env.session.registerActivity()
            }
            .onReceive(inactivityTimer) { _ in env.session.lockIfTimedOut() }
            .onAppear { env.theme.morphMesh(); updateShakeDetector() }
            .onDisappear { shakeDetector.stop() }
            .onChange(of: env.settings.shakeToLock) { _, _ in updateShakeDetector() }
            .onChange(of: scenePhase) { _, _ in updateShakeDetector() }
            .onReceive(NotificationCenter.default.publisher(for: .vaultSwitchToSearch)) { _ in
                uiState.selectedTab = .search
            }
            .onReceive(NotificationCenter.default.publisher(for: .vaultSwitchToWatchtower)) { _ in
                uiState.selectedTab = .watchtower
            }
            .onReceive(NotificationCenter.default.publisher(for: .vaultSwitchToItems)) { _ in
                uiState.selectedTab = .items
            }
            // Present the editor for a 2FA login imported via otpauth:// (now that we're unlocked).
            .sheet(item: Binding(get: { env.pendingTOTPImport },
                                 set: { env.pendingTOTPImport = $0 })) { item in
                ItemEditorScreen(target: .draft(item))
            }
            // Re-present an unsaved editor draft recovered from a previous launch (one-shot,
            // separate from the live `editorDraft` capture so a normally-opened editor is never
            // duplicated). `.edit` preserves the existing item id (a save updates, not
            // duplicates); `.draft` continues a new item.
            .sheet(item: $uiState.restoredDraft) { draft in
                ItemEditorScreen(target: draft.isNew ? .draft(draft.item) : .edit(draft.item))
            }
    }

    /// Start/stop shake-to-lock based on the setting + foreground state (no idle battery cost).
    private func updateShakeDetector() {
        if env.settings.shakeToLock, scenePhase == .active {
            shakeDetector.start {
                Haptics.success()
                env.session.lock(viaShake: true)
            }
        } else {
            shakeDetector.stop()
        }
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
        Image(uiImage: tabImage(uiState.selectedTab == tab ? tab.iconSelected : tab.icon))
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

}
