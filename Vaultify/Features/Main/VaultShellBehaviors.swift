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
    /// Reentrancy guard: the acceptance resume is driven by both the recipient
    /// change counter and every foreground activation — only one attempt loop
    /// should run at a time (the CloudKit work is idempotent, but a second
    /// concurrent loop is wasted).
    @State private var resumingShareAcceptance = false
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
            // AutoFill's "Request code" hand-off: open the shared item's standard detail,
            // which already has the Request control for askEachTime TOTP capabilities.
            .sheet(isPresented: Binding(
                get: { env.pendingSharedItemDeepLinkID != nil },
                set: { if !$0 { env.pendingSharedItemDeepLinkID = nil } })
            ) {
                if let itemID = env.pendingSharedItemDeepLinkID {
                    NavigationStack { ItemDetailScreen(itemID: itemID) }
                }
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
                if phase == .active {
                    env.approvalCoordinator.refreshOwnerRequests()
                    // Owner side: re-resolve outgoing share acceptance off-sheet
                    // so a share accepted after the waiting sheet closed still
                    // advances its status (the sheet's own poll is long gone).
                    env.ownerShareRefresher.refresh()
                    // Recipient side: finish any pending acceptance now that we're
                    // foregrounded — the accepted zone may have propagated into
                    // the shared DB since the last attempt (a single early pass
                    // right after accept often finds zero zones).
                    Task { await resumePendingShareAcceptance() }
                }
            }
            .onAppear {
                env.approvalCoordinator.refreshOwnerRequests()
                env.ownerShareRefresher.refresh()
                // A request fetched while the vault was still locked (cold-launch
                // notification tap fills the inbox before this shell exists) is
                // already `first` when we appear — onChange below never fires for
                // it, so the sheet must be presented explicitly here.
                presentNextApprovalIfIdle()
            }
            // Surface the next verified request once no sheet is up. Only THIS
            // request is cleared on finish — a queued second request presents
            // on the next inbox change, never gets silently dropped.
            .onChange(of: env.approvalCoordinator.pendingOwnerRequests.first?.id) { _, _ in
                presentNextApprovalIfIdle()
            }
            .onChange(of: env.approvalCoordinator.autoPresentSuppressed) { _, suppressed in
                if !suppressed { presentNextApprovalIfIdle() }
            }
            // Recipient side: resume a pending share acceptance now that the
            // vault is unlocked (Validation §3 — escrow BEFORE profile publish;
            // idempotent, crash-safe, survives onboarding), then re-project
            // the shared items so lists reflect the accepted/revoked state.
            .task(id: env.approvalCoordinator.recipientChangeCounter) {
                await resumePendingShareAcceptance()
                if let vaultKey = env.session.vaultKey?.bytes {
                    await env.sharedItems.refresh(vaultKey: vaultKey)
                }
            }
            // Recipient side: rendezvous invite inbox (arm + reconcile + accept
            // prompt) — one path for launch/foreground/push-hint (U6).
            .inviteInboxBehaviors()
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
        guard presentedApproval == nil,
              !env.approvalCoordinator.autoPresentSuppressed else { return }
        presentedApproval = env.approvalCoordinator.pendingOwnerRequests.first
    }

    /// Complete an accepted-but-unpublished share: transactional participant
    /// escrow under the Vault Key, then profile publish into every accepted
    /// zone, then arm the shared-DB push subscription. No-op without the flag.
    ///
    /// The accepted CKShare zone can lag `container.accept` by seconds, so the
    /// first pass often enumerates ZERO shared-DB zones. Publishing nothing is
    /// NOT completion — clearing the breadcrumb there permanently disarms the
    /// retry and strands the owner on "accepted". So the breadcrumb is cleared
    /// ONLY once a profile was actually published (≥1 zone); a zero-zone pass
    /// keeps the flag and retries with backoff, and any leftover is picked up
    /// by the next foreground/unlock.
    private func resumePendingShareAcceptance() async {
        guard UserDefaults.standard.bool(forKey: SharedConfig.pendingShareAcceptanceKey),
              let vaultKey = env.session.vaultKey?.bytes,
              !resumingShareAcceptance else { return }
        resumingShareAcceptance = true
        defer { resumingShareAcceptance = false }
        env.settings.approvalModeEnabled = true
        var delay: Duration = .seconds(2)
        for attempt in 0..<6 {
            guard !Task.isCancelled else { return }
            do {
                let identity = try await env.participantEscrow.ensureIdentity(vaultKey: vaultKey)
                let published = try await env.approvalRecipient.completeAcceptance(
                    identity: identity, nowUnixMs: Int64(Date().timeIntervalSince1970 * 1000))
                if published > 0 {
                    await SharedZoneSubscriptionService().ensureSubscribedIfNeeded(settings: env.settings)
                    UserDefaults.standard.removeObject(forKey: SharedConfig.pendingShareAcceptanceKey)
                    return
                }
                // Zero zones: the accept hasn't materialized a shared-DB zone
                // yet. Keep the flag and wait for propagation.
            } catch {
                // Escrow/publish failure — keep the flag, retry.
            }
            if attempt < 5 {
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(15))
            }
        }
        // Flag intentionally left set — a later foreground/unlock, or a visit to
        // "Shared with Me", completes it once the zone is enumerable.
    }

    /// Start/stop shake-to-lock based on the setting + foreground state (no idle battery cost).
    private func updateShakeDetector() {
        if env.settings.shakeToLock, scenePhase == .active {
            shakeDetector.start {
                Haptics.success()
                env.session.lock(deliberate: true)
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
