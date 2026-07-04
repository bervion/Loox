import SwiftUI
import Combine

/// Shared unlocked-shell behaviors applied by BOTH the compact iPhone tab shell
/// (`MainTabView`) and the regular-width iPad/Mac sidebar (`VaultSidebarView`):
/// the copy toast, the editor sheets (otpauth import + recovered draft), auto-lock
/// (inactivity timer + shake), the section-switch notifications, and the mesh morph.
///
/// Extracted so the two layouts stay behavior-identical — only ONE layout is on screen
/// at a time (chosen by `AdaptiveRootView`), so exactly one instance is ever active.
struct VaultShellBehaviors: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(UIStateStore.self) private var uiState
    @Environment(\.scenePhase) private var scenePhase
    @State private var shakeDetector = ShakeToLockService()
    private let inactivityTimer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    func body(content: Content) -> some View {
        @Bindable var uiState = uiState
        content
            .overlay(alignment: .bottom) { CopyToastOverlay() }
            .animation(.spring(duration: 0.3), value: env.clipboard.recentCopyLabel)
            .onChange(of: uiState.selectedTab) { _, _ in
                env.session.registerActivity()
            }
            // Any touch anywhere in the unlocked app refreshes the idle baseline, so active
            // use (scrolling, reading, editing a single screen) no longer trips the auto-lock.
            .userActivityMonitor { env.session.registerActivity() }
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
            // Re-present an unsaved editor draft recovered from a previous launch (one-shot).
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
}

extension View {
    /// Apply the shared unlocked-shell behaviors (see `VaultShellBehaviors`).
    func vaultShellBehaviors() -> some View { modifier(VaultShellBehaviors()) }
}
