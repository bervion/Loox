import SwiftUI

/// Composition root: owns the long-lived stores/services and wires them
/// together. Injected into the SwiftUI environment.
@MainActor @Observable final class AppEnvironment {
    let settings: SettingsStore
    let theme: ThemeStore
    let session: VaultSession
    let store: VaultStore
    let repository: VaultRepository
    let clipboard: ClipboardService
    let cloudSync: CloudSyncService
    /// Schedules sync runs (immediate on unlock/activate, debounced after mutations).
    let syncCoordinator: SyncCoordinator
    let faviconService: FaviconService
    let attachmentStore: AttachmentStore
    /// Restorable UI state (selected tab, per-tab nav depth, in-progress editor draft),
    /// sealed under the Vault Key. Saved on background, re-applied after unlock.
    let uiState: UIStateStore
    /// Approval Mode sharing transport (owner side) + push-driven refresh.
    /// Construction is cheap and touches no CloudKit until a flow runs.
    let approvalShare: ApprovalShareService
    let approvalCoordinator: ApprovalCoordinator
    /// Foreground approval ceremony (Face ID → boundary-aware issuance).
    let approvalCeremony: ApprovalCeremonyService
    /// Recipient-side transport (accepted shares, requests, responses).
    let approvalRecipient: ApprovalRecipientService
    /// Pretty invite links (public-DB locator + fragment-key ciphertext).
    let inviteLinks: InviteLinkService
    /// Loox-to-Loox auto-invite rendezvous (U5 opaque public inbox).
    let inviteInbox: InviteInboxService
    /// Pending-invite queue shared by the quick-path alert AND the
    /// notifications screen (V7).
    let inviteInboxCoordinator: InviteInboxCoordinator
    /// Recipient participant-identity escrow under the Vault Key.
    let participantEscrow: ParticipantEscrowService
    /// Shared-with-me items as first-class read-only projections (V1.2).
    let sharedItems: SharedItemsProjection
    /// Device-local "which items are shared with whom" registry (owner side).
    let sharingStore = SharingStore()
    /// Bounded local history for the notifications screen.
    let notificationHistory = NotificationHistoryStore()

    /// A 2FA login imported from an `otpauth://` link/QR, awaiting the editor. Presented once the
    /// vault is unlocked; cleared when the editor dismisses.
    var pendingTOTPImport: VaultItem?
    /// A shared item id from the AutoFill extension's "Request code" hand-off
    /// (`vaultify://shared-item/<id>`, see `SharedItemDeepLink`). Presented as a
    /// detail sheet once the vault is unlocked; cleared when the sheet dismisses.
    var pendingSharedItemDeepLinkID: String?

    init() {
        let settings = SettingsStore()
        let session = VaultSession(settings: settings)
        let store = VaultStore()
        self.settings = settings
        self.theme = ThemeStore()
        self.session = session
        self.store = store
        let repository = VaultRepository(store: store, session: session)
        self.repository = repository
        self.clipboard = ClipboardService(settings: settings)
        let cloudSync = CloudSyncService(store: store, settings: settings)
        self.cloudSync = cloudSync
        self.syncCoordinator = SyncCoordinator(
            cloudSync: cloudSync,
            repository: repository,
            settings: settings)
        self.faviconService = FaviconService()
        self.attachmentStore = AttachmentStore(session: session)
        self.uiState = UIStateStore(session: session)
        let approvalShare = ApprovalShareService()
        self.approvalShare = approvalShare
        self.approvalCoordinator = ApprovalCoordinator(settings: settings,
                                                       shareService: approvalShare)
        self.approvalCeremony = ApprovalCeremonyService(session: session,
                                                        repository: repository,
                                                        shareService: approvalShare)
        let approvalRecipient = ApprovalRecipientService()
        let participantEscrow = ParticipantEscrowService()
        let inviteLinks = InviteLinkService()
        let inviteInbox = InviteInboxService()
        self.approvalRecipient = approvalRecipient
        self.participantEscrow = participantEscrow
        self.inviteLinks = inviteLinks
        self.inviteInbox = inviteInbox
        self.sharedItems = SharedItemsProjection(recipient: approvalRecipient,
                                                 escrow: participantEscrow)
        self.inviteInboxCoordinator = InviteInboxCoordinator(
            settings: settings, session: session, escrow: participantEscrow,
            inbox: inviteInbox, links: inviteLinks)
        inviteInboxCoordinator.history = notificationHistory
    }

    /// Sync with iCloud if enabled, then refresh the decrypted cache. Routed through
    /// the coordinator so manual/lifecycle syncs and debounced mutation syncs never
    /// overlap (single-flight + follow-up).
    func syncNow() {
        syncCoordinator.syncNow()
    }

    /// Wipe all data and key material (Settings → Erase Vault). Also best-effort
    /// deletes the CloudKit copy (sealed records + recovery envelope) — otherwise the
    /// printed Emergency Kit could resurrect the "erased" vault from iCloud, and a
    /// future vault would pull ghosts sealed under the old key.
    func eraseEverything() {
        Task { [cloudSync] in await cloudSync.eraseRemote() }
        // Approval shares must not outlive the vault that sealed them.
        Task { [approvalShare] in await approvalShare.revokeAllOwned() }
        // Rendezvous inbox dies with the vault (descriptor + subscription).
        Task { [inviteInbox] in await inviteInbox.disarm() }
        sharingStore.wipe()
        sharedItems.wipe()
        notificationHistory.wipe()
        // The AutoFill shared-credentials cache outlives an ordinary lock by design
        // (see SharedCredentialsCache) — Erase Vault is the one place it must go too.
        SharedCredentialsCache.clear()
        VaultKeyEscrowService.clearPushedFingerprint()
        // Approval Mode device-local state dies with the vault (full CloudKit
        // approval-artifact teardown is the revocation phase's job).
        ParticipantEscrowService.clearLocalCache()
        SharedZoneSubscriptionService.clearLocalFlag()
        settings.approvalModeEnabled = false
        settings.iCloudSyncEnabled = false
        repository.clear()
        try? store.eraseAll()
        uiState.wipe()
        session.resetVault()
    }
}
