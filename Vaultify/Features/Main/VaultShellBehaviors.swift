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
    /// The request whose ceremony sheet is currently up. Decoupled from the
    /// coordinator inbox on purpose: inbox refreshes must not swap the sheet
    /// mid-ceremony, and dismissing must not clear the NEXT pending request.
    @State private var presentedApproval: ApprovalCoordinator.PendingOwnerRequest?
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
            // Owner approval ceremony (ADR-1): the shell only exists while the
            // vault is unlocked, so a surfaced request can go straight to the
            // verified sheet. Pushes are best-effort — refresh the inbox on
            // every foreground activation too, so a missed push can't strand B.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { env.approvalCoordinator.refreshOwnerRequests() }
            }
            .onAppear { env.approvalCoordinator.refreshOwnerRequests() }
            // Surface the next verified request once no sheet is up. Only THIS
            // request is cleared on finish — a queued second request presents
            // on the next inbox change, never gets silently dropped.
            .onChange(of: env.approvalCoordinator.pendingOwnerRequests.first?.id) { _, _ in
                presentNextApprovalIfIdle()
            }
            // Recipient side: resume a pending share acceptance now that the
            // vault is unlocked (Validation §3 — escrow BEFORE profile publish;
            // idempotent, crash-safe, survives onboarding).
            .task(id: env.approvalCoordinator.recipientChangeCounter) {
                await resumePendingShareAcceptance()
            }
            .sheet(item: $presentedApproval) { pending in
                ApprovalRequestSheet(
                    pending: pending,
                    itemTitle: env.repository.item(id: pending.request.itemId)?.title
                        ?? appString("an item"),
                    onFinished: {
                        env.approvalCoordinator.clearPending(requestId: pending.request.requestId)
                    })
            }
    }

    private func presentNextApprovalIfIdle() {
        guard presentedApproval == nil else { return }
        presentedApproval = env.approvalCoordinator.pendingOwnerRequests.first
    }

    /// Complete an accepted-but-unpublished share: transactional participant
    /// escrow under the Vault Key, then profile publish into every accepted
    /// zone, then arm the shared-DB push subscription. No-op without the flag.
    private func resumePendingShareAcceptance() async {
        guard UserDefaults.standard.bool(forKey: SharedConfig.pendingShareAcceptanceKey),
              let vaultKey = env.session.vaultKey?.bytes else { return }
        env.settings.approvalModeEnabled = true
        do {
            let identity = try await env.participantEscrow.ensureIdentity(vaultKey: vaultKey)
            try await env.approvalRecipient.completeAcceptance(
                identity: identity, nowUnixMs: Int64(Date().timeIntervalSince1970 * 1000))
            await SharedZoneSubscriptionService().ensureSubscribedIfNeeded(settings: env.settings)
            UserDefaults.standard.removeObject(forKey: SharedConfig.pendingShareAcceptanceKey)
        } catch {
            // Flag stays set — retried on the next unlock/foreground pass.
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
