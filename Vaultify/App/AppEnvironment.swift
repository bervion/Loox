import Foundation
import SwiftUI

/// Composition root: owns the long-lived stores/services and wires them
/// together. Injected into the SwiftUI environment.
@MainActor @Observable final class AppEnvironment {
    let uiTestConfiguration: UITestConfiguration
    let settings: SettingsStore
    let theme: ThemeStore
    let session: VaultSession
    let store: VaultStore
    let repository: VaultRepository
    /// Email-relay control plane (alias activate/disable/delete, erase teardown).
    let relay: RelayService
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
    let sharingStore: SharingStore
    /// Off-sheet refresh of outgoing share lifecycle (foreground/unlock), so an
    /// acceptance landing after the waiting sheet closed still advances status.
    let ownerShareRefresher: OwnerShareRefresher
    /// Publishes the grant once the recipient's profile lands, replaying the
    /// scope the owner froze at create time (no second owner pass).
    let shareActivation: ShareActivationService
    /// Loox Link quick shares: encrypted snapshot links (key in URL fragment).
    let looxLinks: LooxLinkService
    /// Layer-A network-path precondition for the shared-vault access gate
    /// (INV-02 — a satisfied path is never an authorization by itself).
    let reachability: NetworkReachabilityMonitor
    /// Optional-capability state (Share Link / Private Email): user prefs,
    /// last verified operator modes, health, per-service circuit breakers.
    let capabilities: CapabilityStore
    /// Signed capability-manifest client (LOOX-CAP-MANIFEST-V1): verified
    /// cache re-applied at init (local, no network); refresh runs from the
    /// capability screens' probe — never on the startup critical path.
    let capabilityManifest: CapabilityManifestClient
    /// Signed auxiliary-domain registry client (LOOX-DOMAIN-REGISTRY-V1):
    /// same cache-then-probe posture as the manifest; feeds the trusted
    /// domain set behind Private Email / short links.
    let domainRegistry: DomainRegistryClient
    /// Bounded local history for the notifications screen.
    let notificationHistory: NotificationHistoryStore
    /// Quick View ("Send to Browser") device-local attempt history — minimal
    /// rows only (item id + timestamp + result).
    let quickViewHistory: QuickViewHistoryStore
    /// Signed Quick View runtime session-signer endorsement client
    /// (LOOX-QUICK-VIEW-SIGNER-KEYSET-V1) — resolves which key must validate
    /// a scanned/typed session's SESSION-V1 signature (DEC-QV-SIGN-01).
    let quickViewSignerKeyset: QuickViewSignerKeysetClient
    /// Centralized lifecycle refresher for every signed control-plane document —
    /// keeps the manifest/registry/keyset fresh from launch-after-unlock and
    /// foreground, so freshness never depends on visiting a feature screen
    /// (INV-CP-01). Non-blocking; assigned once all three clients exist.
    let controlPlaneRefresher: SignedControlPlaneRefresher
    /// Loox tier from verified StoreKit 2 transactions (Free when none).
    /// Entitlement state gates offers/quotas only — never vault data.
    let entitlements: LooxEntitlementStore
    /// B3 attach orchestration (dormant): grants/leases for the backend
    /// entitlement service, fed to the relay/link/quick-view clients through
    /// `LooxEntitlementClientHooks`. Enforces nothing until B5.
    let entitlementCoordinator: LooxEntitlementCoordinator

    /// A 2FA login imported from an `otpauth://` link/QR, awaiting the editor. Presented once the
    /// vault is unlocked; cleared when the editor dismisses.
    var pendingTOTPImport: VaultItem?
    /// A shared item id from the AutoFill extension's "Request code" hand-off
    /// (`vaultify://shared-item/<id>`, see `SharedItemDeepLink`). Presented as a
    /// detail sheet once the vault is unlocked; cleared when the sheet dismisses.
    var pendingSharedItemDeepLinkID: String?

    init(uiTestConfiguration: UITestConfiguration = .current) {
        self.uiTestConfiguration = uiTestConfiguration
        #if DEBUG
        // Hosted unit/snapshot bundles launch the app before the test case can
        // inject its own environment. Treat that host process exactly like a UI
        // test for persistence/network purposes so it cannot touch a developer's
        // simulator vault, Keychain, App Group, preferences, or control plane.
        let testIsolationEnabled = uiTestConfiguration.isEnabled
            || CloudSyncService.isHostingUnitTests
        let settingsDefaults = testIsolationEnabled
            ? UITestConfiguration.makeIsolatedSettingsDefaults()
            : UserDefaults.standard
        let isolatedFileRoot = testIsolationEnabled
            ? UITestConfiguration.makeIsolatedFileRoot()
            : nil
        #else
        let testIsolationEnabled = false
        let settingsDefaults = UserDefaults.standard
        let isolatedFileRoot: URL? = nil
        #endif
        let settings = SettingsStore(
            defaults: settingsDefaults,
            mirrorToSharedConfig: !testIsolationEnabled
        )
        #if DEBUG
        if testIsolationEnabled {
            settings.analyticsEnabled = false
            settings.iCloudSyncEnabled = false
            settings.approvalModeEnabled = false
            settings.biometricUnlockEnabled = false
            settings.rotationRemindersEnabled = false
            settings.showWebsiteIcons = false
            settings.hideInAppSwitcher = false
            settings.autoLock = .immediate
            settings.preferredLanguage = "en"
            settings.onboardingCompleted = true
            settings.hasChosenAppearance = true
        }
        #endif
        let session = VaultSession(
            settings: settings,
            uiTestConfiguration: uiTestConfiguration,
            persistentKeyMaterialEnabled: !testIsolationEnabled
        )
        let store = VaultStore(inMemory: testIsolationEnabled)
        self.settings = settings
        #if DEBUG
        self.theme = ThemeStore(
            forceLight: testIsolationEnabled || !settings.hasChosenAppearance,
            settingsOverride: testIsolationEnabled ? .default : nil,
            systemIsDarkOverride: testIsolationEnabled ? false : nil,
            persistChanges: !testIsolationEnabled
        )
        #else
        self.theme = ThemeStore(
            forceLight: !settings.hasChosenAppearance,
            settingsOverride: nil,
            systemIsDarkOverride: nil,
            persistChanges: true
        )
        #endif
        self.session = session
        self.store = store
        self.sharingStore = SharingStore(defaults: settingsDefaults)
        self.looxLinks = LooxLinkService(persistenceEnabled: !testIsolationEnabled)
        self.notificationHistory = NotificationHistoryStore(defaults: settingsDefaults)
        self.quickViewHistory = QuickViewHistoryStore(
            persistenceEnabled: !testIsolationEnabled
        )
        self.entitlementCoordinator = LooxEntitlementCoordinator(
            externalSideEffectsEnabled: !testIsolationEnabled
        )
        let repository = VaultRepository(
            store: store,
            session: session,
            externalSideEffectsEnabled: !testIsolationEnabled
        )
        self.repository = repository
        self.relay = RelayService(repository: repository, session: session)
        // Capability state: never consulted by the Core Vault (INV-CAP-01);
        // built from locals (two-phase init), wired into services at the end.
        let reachability = NetworkReachabilityMonitor(
            monitoringEnabled: !testIsolationEnabled,
            initialSatisfied: false
        )
        self.reachability = reachability
        let capabilities = CapabilityStore(reachability: reachability, defaults: settingsDefaults)
        self.capabilities = capabilities
        self.capabilityManifest = CapabilityManifestClient(
            store: capabilities,
            defaults: settingsDefaults
        )
        let domainRegistry = DomainRegistryClient(defaults: settingsDefaults)
        self.domainRegistry = domainRegistry
        let quickViewSignerKeyset = QuickViewSignerKeysetClient(defaults: settingsDefaults)
        self.quickViewSignerKeyset = quickViewSignerKeyset
        self.controlPlaneRefresher = SignedControlPlaneRefresher(
            documents: [self.capabilityManifest, domainRegistry, quickViewSignerKeyset])
        self.clipboard = ClipboardService(settings: settings)
        let cloudSync = CloudSyncService(store: store, settings: settings)
        self.cloudSync = cloudSync
        self.syncCoordinator = SyncCoordinator(
            cloudSync: cloudSync,
            repository: repository,
            settings: settings)
        self.faviconService = FaviconService(
            cacheDirectory: isolatedFileRoot?.appending(path: "Favicons")
        )
        self.attachmentStore = AttachmentStore(
            session: session,
            directory: isolatedFileRoot?.appending(path: "Attachments")
        )
        self.uiState = UIStateStore(
            session: session,
            fileURL: isolatedFileRoot?.appending(path: "ui-state.enc")
        )
        let approvalShare = ApprovalShareService()
        self.approvalShare = approvalShare
        self.approvalCoordinator = ApprovalCoordinator(
            settings: settings,
            shareService: approvalShare,
            defaults: settingsDefaults
        )
        let approvalRecipient = ApprovalRecipientService()
        let participantEscrow = ParticipantEscrowService()
        let inviteLinks = InviteLinkService()
        let inviteInbox = InviteInboxService()
        // Built before the refresher: the refresher finishes a share the moment
        // the recipient's profile lands, so it needs the activator in hand.
        let shareActivation = ShareActivationService(
            sharingStore: sharingStore, shareService: approvalShare,
            repository: repository, session: session, store: store,
            inviteLinks: inviteLinks)
        self.shareActivation = shareActivation
        self.ownerShareRefresher = OwnerShareRefresher(
            store: sharingStore, shareService: approvalShare, settings: settings,
            notifier: ShareStatusNotifier(), activation: shareActivation)
        self.approvalCeremony = ApprovalCeremonyService(session: session,
                                                        repository: repository,
                                                        shareService: approvalShare,
                                                        store: store)
        self.approvalRecipient = approvalRecipient
        self.participantEscrow = participantEscrow
        self.inviteLinks = inviteLinks
        self.inviteInbox = inviteInbox
        self.sharedItems = SharedItemsProjection(
            recipient: approvalRecipient,
            escrow: participantEscrow,
            defaults: settingsDefaults
        )
        self.inviteInboxCoordinator = InviteInboxCoordinator(
            settings: settings, session: session, escrow: participantEscrow,
            inbox: inviteInbox, links: inviteLinks)
        inviteInboxCoordinator.history = notificationHistory
        self.entitlements = LooxEntitlementStore(defaults: settingsDefaults)
        // All stored properties are set — safe to wire the capability sinks
        // (weak refs; one independent breaker per service, INV-CAP-03).
        relay.capabilities = capabilities
        looxLinks.capabilities = capabilities
        // Local-only cache re-verify (no network; INV-CAP-02 intact).
        if !testIsolationEnabled {
            capabilityManifest.applyCached()
            domainRegistry.applyCached()
            quickViewSignerKeyset.applyCached()
        }
        // The push delegate exists before this environment does — hand it
        // weak references so a silent push can hold its fetch completion
        // handler until the triggered CloudKit work actually finishes.
        if !testIsolationEnabled {
            SilentPushWork.shareRefresher = ownerShareRefresher
            SilentPushWork.syncCoordinator = syncCoordinator
        }
        // StoreKit transaction listener must run from launch so purchases,
        // renewals and refunds land without a restart.
        if !testIsolationEnabled {
            entitlements.start()
        }
        // B3 seams: service clients pull lease/grant payloads and the
        // refresh-required recovery from the coordinator; every verified
        // transaction update (purchase, renewal, restore) re-attaches.
        let entitlementCoordinator = self.entitlementCoordinator
        LooxEntitlementClientHooks.payloadProvider = { service in
            await entitlementCoordinator.payload(for: service)
        }
        LooxEntitlementClientHooks.refreshHandler = {
            await entitlementCoordinator.refreshAndReport()
        }
        entitlements.onVerifiedTransactionUpdate = { [weak self] in
            Task { await entitlementCoordinator.attachNow() }
            // The tier user property follows VERIFIED transactions (purchase,
            // renewal, refund, restore) — the same signal that grants the tier.
            Task { @MainActor in
                guard let self else { return }
                AnalyticsEngine.shared.refreshUserProperties(
                    tier: self.entitlements.tier,
                    language: self.settings.preferredLanguage,
                    iCloudSyncEnabled: self.settings.iCloudSyncEnabled)
            }
        }
        #if DEBUG
        if uiTestConfiguration.isEnabled {
            do {
                try UITestFixtures.install(uiTestConfiguration, store: store, repository: repository)
                // Exercise the declared critical journey from its real initial
                // boundary: the fixture is present, but the user must unlock
                // before any vault content becomes visible. The panic-restart
                // fixture launches without this automatic lock — its test
                // performs the deliberate lock through the real Settings
                // control and verifies the state survives a relaunch.
                if uiTestConfiguration.fixture == .vaultEditSaveRelock {
                    session.lock(deliberate: true)
                }
            } catch {
                preconditionFailure("Unable to install deterministic UI-test fixture: \(error)")
            }
        }
        #endif
    }

    /// Sync with iCloud if enabled, then refresh the decrypted cache. Routed through
    /// the coordinator so manual/lifecycle syncs and debounced mutation syncs never
    /// overlap (single-flight + follow-up).
    func syncNow() {
        guard !uiTestConfiguration.isEnabled else { return }
        syncCoordinator.syncNow()
    }

    /// Releases the onboarding forced-light gate (see `ThemeStore.forceLight`) — the
    /// user made an explicit appearance choice, or onboarding completed without one
    /// (e.g. restoring an existing vault, which skips the ChooseTheme step).
    /// Idempotent. Keeps `SettingsStore.hasChosenAppearance` (persistence) and
    /// `ThemeStore.forceLight` (live rendering) in lockstep — every call site that
    /// releases the gate goes through here rather than touching both stores itself.
    func markAppearanceChosen() {
        theme.markAppearanceChosen()
        settings.hasChosenAppearance = true
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
        eraseLocalState()
    }

    /// One-shot flag: RootView presents the "this device was signed out" alert once
    /// the erase below lands the user on onboarding.
    var remoteSignOutNotice = false
    private var remoteSignOutHandled = false

    /// A remote "Log Out Device" marker was found for THIS device (see
    /// `DeviceRegistryService`): erase LOCAL state only — the vault lives on in
    /// iCloud and on the owner's other devices, so none of `eraseEverything`'s
    /// remote teardown may run — retire this device's registry identity so a
    /// future re-pair isn't wiped by the same marker, and land on onboarding.
    func handleRemoteSignOut() {
        guard !remoteSignOutHandled else { return }
        remoteSignOutHandled = true
        // Best-effort: remove our registry row while credentials still work.
        let registry = DeviceRegistryService(settings: settings)
        Task { await registry.deleteOwnRecord() }
        eraseLocalState()
        DeviceRegistryService.resetIdentityAfterRemoteSignOut()
        remoteSignOutNotice = true
    }

    /// The device-local portion of a vault erase — shared by Settings → Erase Vault
    /// (which also tears down the remote copy) and a remote sign-out (which must not).
    private func eraseLocalState() {
        sharingStore.wipe()
        // Quick-link revoke tokens die with the vault; the links themselves
        // expire server-side (we can't revoke without the tokens anyway).
        looxLinks.records.wipe()
        sharedItems.wipe()
        notificationHistory.wipe()
        quickViewHistory.wipe()
        // The AutoFill shared-credentials cache and the projection snapshot outlive
        // an ordinary lock by design (sealed at rest) — Erase Vault is the one
        // place they must go too.
        SharedCredentialsCache.clear()
        SharedItemsProjection.clearPersisted()
        // Known-leak lookup cache carries HMAC-keyed signals about the erased
        // vault's passwords — file + Keychain secret go too.
        AuditLocalCache.clearPersisted()
        VaultKeyEscrowService.clearPushedFingerprint()
        // Approval Mode device-local state dies with the vault (full CloudKit
        // approval-artifact teardown is the revocation phase's job).
        ParticipantEscrowService.clearLocalCache()
        // Relay Principal: local cache dies here; the remote escrow record dies
        // with the "Vault" zone that eraseRemote() drops (no extra remote call).
        RelayPrincipalEscrowService.clearLocalCache()
        SharedZoneSubscriptionService.clearLocalFlag()
        DeviceRegistryMirror.clear()
        settings.approvalModeEnabled = false
        settings.iCloudSyncEnabled = false
        repository.clear()
        try? store.eraseAll()
        uiState.wipe()
        session.resetVault()
    }
}
