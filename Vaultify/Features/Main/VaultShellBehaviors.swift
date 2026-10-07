import SwiftUI
import Combine

/// Shared unlocked-shell behaviors applied by BOTH the compact iPhone tab shell
/// (`MainTabView`) and the regular-width iPad/Mac sidebar (`VaultSidebarView`):
/// the copy toast, the editor sheets (otpauth import + recovered draft), auto-lock
/// (the inactivity timer; shake-to-lock is armed at the app root instead, since a pushed
/// screen must not disarm a panic gesture), the section-switch notifications, and the mesh morph.
///
/// Extracted so the two layouts stay behavior-identical — only ONE layout is on screen
/// at a time (chosen by `AdaptiveRootView`), so exactly one instance is ever active.
struct VaultShellBehaviors: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(UIStateStore.self) private var uiState
    @Environment(\.scenePhase) private var scenePhase
    /// The request whose ceremony sheet is currently up. Decoupled from the
    /// coordinator inbox on purpose: inbox refreshes must not swap the sheet
    /// mid-ceremony, and dismissing must not clear the NEXT pending request.
    @State private var presentedApproval: ApprovalCoordinator.PendingOwnerRequest?
    /// Reentrancy guard: the acceptance resume is driven by both the recipient
    /// change counter and every foreground activation — only one attempt loop
    /// should run at a time (the CloudKit work is idempotent, but a second
    /// concurrent loop is wasted).
    @State private var resumingShareAcceptance = false
    /// The outgoing share whose "they accepted" banner the owner tapped —
    /// presents the resume stepper (fingerprint ceremony) once the unlocked
    /// shell is up and no other ceremony sheet is showing.
    @State private var resumeShareFromTap: ItemShareRecord?
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
            .onAppear { env.theme.morphMesh() }
            .onReceive(NotificationCenter.default.publisher(for: .vaultSwitchToWatchtower)) { _ in
                uiState.selectedTab = .watchtower
            }
            .onReceive(NotificationCenter.default.publisher(for: .vaultSwitchToItems)) { _ in
                uiState.selectedTab = .items
            }
            // Present the editor for a 2FA login imported via otpauth:// (now that we're unlocked).
            // A handed-back draft of the SAME item supersedes this trigger: the import
            // request outlives a shell teardown (it lives on `env`), so both sheets would
            // otherwise fire at once — one pristine, one with the user's typed values —
            // and SwiftUI would drop whichever lost the race.
            .sheet(item: Binding(get: { pendingTOTPImportUnlessHandedBack },
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
            // Re-present an unsaved editor draft that lost its host: recovered from a
            // previous launch, or handed back when a size-class flip tore this shell
            // down mid-edit. Both shells apply this modifier, so the draft lands in
            // whichever layout comes up next.
            .sheet(item: $uiState.restoredDraft) { draft in
                ItemEditorScreen(target: .restored(draft))
            }
            // Quick actions the SHELL owns (see `UIStateStore.QuickSheet`), so a
            // layout swap re-presents them instead of dropping them with the
            // layout's own state.
            .sheet(item: $uiState.quickSheet) { sheet in
                switch sheet {
                case .generator: GeneratorScreen()
                case .totpCodes: TotpListScreen(presentedAsSheet: true)
                }
            }
            // Owner approval ceremony (ADR-1): the shell only exists while the
            // vault is unlocked, so a surfaced request can go straight to the
            // verified sheet. Pushes are best-effort — refresh the inbox on
            // every foreground activation too, so a missed push can't strand B.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, !env.uiTestConfiguration.isEnabled {
                    env.approvalCoordinator.refreshOwnerRequests()
                    // Owner side: re-resolve outgoing share acceptance off-sheet
                    // so a share accepted after the waiting sheet closed still
                    // advances its status (the sheet's own poll is long gone).
                    env.ownerShareRefresher.refresh()
                    // A buffered banner tap that couldn't present earlier (an
                    // approval ceremony was up) gets another chance now.
                    drainShareResumeTap()
                    // Recipient side: finish any pending acceptance now that we're
                    // foregrounded — the accepted zone may have propagated into
                    // the shared DB since the last attempt (a single early pass
                    // right after accept often finds zero zones).
                    Task { await resumePendingShareAcceptance() }
                }
            }
            .onAppear {
                // First, before anything can present: a draft whose editor was torn
                // down with the previous shell (size-class flip) is re-armed here when
                // the outgoing editor reported its unmount only after this shell came
                // up. Ordering between the two is not guaranteed, so both ends ask.
                uiState.rehydrateEditorIfNeeded()
                guard !env.uiTestConfiguration.isEnabled else { return }
                env.approvalCoordinator.refreshOwnerRequests()
                env.ownerShareRefresher.refresh()
                // Drain a tapped share-acceptance banner BEFORE the ambient
                // approval auto-present: the tap is an explicit user gesture,
                // so its sheet outranks a queued request (which re-presents on
                // the next inbox change either way).
                drainShareResumeTap()
                // A request fetched while the vault was still locked (cold-launch
                // notification tap fills the inbox before this shell exists) is
                // already `first` when we appear — onChange below never fires for
                // it, so the sheet must be presented explicitly here.
                presentNextApprovalIfIdle()
            }
            .onDisappear {
                // This shell leaves for exactly two reasons. A layout swap keeps the
                // shell-owned quick sheet, so the next layout puts it straight back up.
                // A lock drops it: the vault should come back the way the user left it,
                // not with a sheet the lock screen interrupted.
                if env.session.state != .unlocked { uiState.quickSheet = nil }
            }
            // Warm path: the owner tapped the "they accepted" banner while the
            // unlocked shell is already on screen.
            .onReceive(NotificationCenter.default.publisher(for: .shareResumeTapRequested)) { _ in
                drainShareResumeTap()
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
                guard !env.uiTestConfiguration.isEnabled else { return }
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
            // Resume stepper for a tapped "they accepted" banner (owner side).
            .sheet(item: $resumeShareFromTap) { ShareResumeStepperSheet(share: $0) }
    }

    /// The pending otpauth import, unless the same item is already coming back as a
    /// handed-back draft (see the sheet above).
    private var pendingTOTPImportUnlessHandedBack: VaultItem? {
        guard let pending = env.pendingTOTPImport else { return nil }
        return uiState.restoredDraft?.id == pending.id ? nil : pending
    }

    private func presentNextApprovalIfIdle() {
        // The banner-tap resume sheet counts as busy too: an explicit tap
        // outranks the ambient auto-present, and a queued request re-presents
        // on the next inbox change rather than being dropped.
        guard presentedApproval == nil, resumeShareFromTap == nil,
              !env.approvalCoordinator.autoPresentSuppressed else { return }
        presentedApproval = env.approvalCoordinator.pendingOwnerRequests.first
    }

    /// Present the resume stepper for the share buffered by a banner tap.
    /// Never fights a sheet already up — a mid-flight approval ceremony must
    /// not be swapped out — so the mailbox keeps the tap until a drain finds
    /// the way clear (next foreground pass retries). A share that was revoked
    /// or finished in the meantime drains to nothing.
    private func drainShareResumeTap() {
        guard let zoneName = PendingShareResumeTap.zoneName else { return }
        guard presentedApproval == nil, resumeShareFromTap == nil else { return }
        PendingShareResumeTap.zoneName = nil
        resumeShareFromTap = env.sharingStore.shares.first { $0.zoneName == zoneName }
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
        guard !env.uiTestConfiguration.isEnabled else { return }
        let flag = UserDefaults.standard.bool(forKey: SharedConfig.pendingShareAcceptanceKey)
        let unlocked = env.session.vaultKey != nil
        guard flag, let vaultKey = env.session.vaultKey?.bytes, !resumingShareAcceptance else {
            ShareDiagnostics.log("RESUME", "skip flag=\(flag) unlocked=\(unlocked) "
                + "inFlight=\(resumingShareAcceptance)")
            return
        }
        resumingShareAcceptance = true
        defer { resumingShareAcceptance = false }
        env.settings.approvalModeEnabled = true
        ShareDiagnostics.log("RESUME", "begin (flag set, unlocked)")
        var delay: Duration = .seconds(2)
        for attempt in 0..<6 {
            guard !Task.isCancelled else { ShareDiagnostics.log("RESUME", "cancelled"); return }
            do {
                let identity = try await env.participantEscrow.ensureIdentity(vaultKey: vaultKey)
                let published = try await env.approvalRecipient.completeAcceptance(
                    identity: identity, nowUnixMs: Int64(Date().timeIntervalSince1970 * 1000))
                ShareDiagnostics.log("RESUME", "attempt \(attempt): published=\(published)")
                if published > 0 {
                    await SharedZoneSubscriptionService().ensureSubscribedIfNeeded(settings: env.settings)
                    UserDefaults.standard.removeObject(forKey: SharedConfig.pendingShareAcceptanceKey)
                    ShareDiagnostics.log("RESUME", "DONE (breadcrumb cleared)")
                    return
                }
                // Zero zones: the accept hasn't materialized a shared-DB zone
                // yet. Keep the flag and wait for propagation.
            } catch {
                ShareDiagnostics.log("RESUME", "attempt \(attempt) ERROR: \(error)")
            }
            if attempt < 5 {
                try? await Task.sleep(for: delay)
                delay = min(delay * 2, .seconds(15))
            }
        }
        ShareDiagnostics.log("RESUME", "exhausted retries — flag kept")
        // Flag intentionally left set — a later foreground/unlock, or a visit to
        // "Shared with Me", completes it once the zone is enumerable.
    }

}

extension View {
    /// Apply the shared unlocked-shell behaviors (see `VaultShellBehaviors`).
    func vaultShellBehaviors() -> some View { modifier(VaultShellBehaviors()) }
}
