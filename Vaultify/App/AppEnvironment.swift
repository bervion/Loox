import Foundation
import SwiftUI

/// Composition root: owns the long-lived stores/services and wires them
/// together. Injected into the SwiftUI environment.
@MainActor @Observable final class AppEnvironment {
    let uiTestConfiguration: UITestConfiguration
    #if DEBUG
    /// Root of the throwaway file tree an isolated launch writes into (favicon
    /// cache, attachments, artifacts, UI state). Exposed so a test can assert
    /// what an erase leaves behind on disk; nil outside isolation.
    @ObservationIgnored let isolatedFileRoot: URL?
    #endif
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
    /// First-class encrypted artifact lifecycle (per-artifact DEKs, staged
    /// import, recovery journal). Supersedes `attachmentStore`'s vault-key
    /// sidecar blobs; the legacy store stays alive for reads + lazy adoption.
    let artifactStore: ArtifactStore
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
    /// Runs the in-app guided tours (spotlight + tooltip). Inert while
    /// `TutorialFeature.enabled` is false or every flow has been answered.
    let tutorial: TutorialCoordinator
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
    /// The single erase state machine for every platform (iOS Settings and the
    /// macOS Settings window both drive this one object).
    let erase = EraseFlow()

    /// Whether the remote teardown steps may talk to CloudKit and the link
    /// service at all. False under test isolation, where `CKContainer.init`
    /// traps in a host process without the iCloud entitlement.
    @ObservationIgnored private let remoteTeardownEnabled: Bool

    /// A 2FA login imported from an `otpauth://` link/QR, awaiting the editor. Presented once the
    /// vault is unlocked; cleared when the editor dismisses.
    var pendingTOTPImport: VaultItem?
    /// A shared item id from the AutoFill extension's "Request code" hand-off
    /// (`vaultify://shared-item/<id>`, see `SharedItemDeepLink`). Presented as a
    /// detail sheet once the vault is unlocked; cleared when the sheet dismisses.
    var pendingSharedItemDeepLinkID: String?

    #if DEBUG
    /// Opt back INTO the guided tours under test isolation. Isolated launches
    /// skip every tour by default (see `init`), so a test that wants to drive
    /// one asks for it explicitly — as a launch argument, or as the Maestro
    /// equivalent written into the argument domain.
    static let tutorialLaunchArgument = "-ui-test-tutorials"

    /// Launch argument ONLY.
    ///
    /// A `UserDefaults.standard` fallback used to be accepted here, and it
    /// re-globalised the very thing this opt-in exists to keep per-test: a test
    /// that set the key and then died before its cleanup left it written into
    /// the app's real defaults on that simulator, so every later launch showed
    /// the first-run scrim and both UI tests failed. Launch arguments die with
    /// the process, which is the property we actually want.
    static var tutorialsRequestedByTest: Bool {
        ProcessInfo.processInfo.arguments.contains(tutorialLaunchArgument)
    }

    /// Opt back INTO the story intro under test isolation — same launch-argument-only
    /// contract as the tutorials arg above (a defaults fallback would leak across
    /// tests; arguments die with the process).
    static let storyLaunchArgument = "-ui-test-story"

    static var storyRequestedByTest: Bool {
        ProcessInfo.processInfo.arguments.contains(storyLaunchArgument)
    }
    #endif

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
        #if DEBUG
        self.isolatedFileRoot = isolatedFileRoot
        #endif
        self.remoteTeardownEnabled = !testIsolationEnabled
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
            // The story intro is a full-screen route that would strand every
            // existing UI test on a non-hittable cinematic — completed by
            // default, opt back in per test via the launch argument.
            settings.storyIntroCompleted = !Self.storyRequestedByTest
            settings.storyIntroWantsFirstItem = false
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
        let tutorialStore = TutorialStore(defaults: settingsDefaults)
        self.tutorial = TutorialCoordinator(store: tutorialStore)
        #if DEBUG
        // A first-run tour draws a full-screen scrim, and everything under a
        // scrim is non-hittable — a UI test that never asked for a tour was
        // failing on the tap that landed on it instead of on the row. Isolated
        // launches therefore start with every flow already answered.
        if testIsolationEnabled, !Self.tutorialsRequestedByTest {
            for flowID in TutorialFlow.allFlowIDs { tutorialStore.mark(flowID, .skipped) }
        }
        #endif
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
        self.artifactStore = ArtifactStore(
            session: session,
            store: store,
            directory: isolatedFileRoot?.appending(path: "Artifacts-v2")
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
        erase.attach(to: self)
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

    // MARK: Erase

    /// How long any single remote teardown step may take before it is reported
    /// as "still live". A hung request must not hold an erase open forever, and
    /// the user gets Retry either way.
    private static let eraseStepBudget: Duration = .seconds(25)

    /// Erase everything Loox stored on THIS device. Remote copies are
    /// deliberately untouched: the iCloud vault, quick links, private-email
    /// aliases and shared logins all stay exactly as they are.
    func eraseThisDevice() {
        // Nothing remote was torn down, so every revoke token this device holds
        // is still the only thing that can kill those links. Keep them.
        eraseLocalState(retainingLinkRecords: liveQuickLinks)
    }

    /// Complete an erase once the remote teardown outcome is known.
    /// `retainingLinks` are the quick links that are still live: destroying
    /// their revoke tokens with the vault is what turned a temporary failure
    /// into up to 30 days of ciphertext nobody could ever kill.
    func finishErase(retainingLinks: [LooxLinkRecord]) {
        eraseLocalState(retainingLinkRecords: retainingLinks)
    }

    /// Quick links this device created that have not expired yet.
    var liveQuickLinks: [LooxLinkRecord] {
        looxLinks.records.records.filter { !$0.isExpired }
    }

    /// Tear down the remote surfaces an "erase everywhere" is responsible for,
    /// and report what actually happened per step.
    ///
    /// Runs BEFORE any local wipe, and touches nothing local itself: the
    /// credentials these calls need — quick-link revoke tokens, the relay
    /// principal key, the approval-zone registry — are exactly what
    /// `eraseLocalState()` destroys. Every step is individually bounded so one
    /// unreachable service cannot hold the whole erase open.
    func tearDownRemoteState(steps: [EraseStep]) async -> EraseTeardownReport {
        var report = EraseTeardownReport()
        guard remoteTeardownEnabled else {
            for step in steps { report.record(.nothingToDo(step)) }
            return report
        }
        for step in steps {
            switch step {
            case .quickLinks:
                let live = liveQuickLinks
                guard !live.isEmpty else { report.record(.nothingToDo(step)); continue }
                let result = await Self.bounded(timedOut: (attempted: live.count, failed: live)) {
                    [looxLinks] in await looxLinks.revokeAllForErase()
                }
                report.unrevokedLinks = result.failed
                report.record(EraseStepOutcome(step: step, attempted: result.attempted,
                                               failed: result.failed.count))

            case .emailAliases:
                let active = repository.aliases.filter { $0.status == .active }
                guard !active.isEmpty else { report.record(.nothingToDo(step)); continue }
                let ok = await Self.bounded(timedOut: false) { [relay] in
                    do { try await relay.disableAllForErase(); return true } catch { return false }
                }
                report.record(EraseStepOutcome(step: step, attempted: active.count,
                                               failed: ok ? 0 : active.count))

            case .approvalShares:
                guard settings.approvalModeEnabled || !ApprovalShareService.ownedZoneNames.isEmpty else {
                    report.record(.nothingToDo(step)); continue
                }
                let result = await Self.bounded(timedOut: (attempted: 1, failed: 1)) {
                    [approvalShare] in await approvalShare.revokeAllOwned()
                }
                report.record(EraseStepOutcome(step: step, attempted: result.attempted,
                                               failed: result.failed))

            case .inviteInbox:
                guard InviteInboxService.hasPublishedInbox else {
                    report.record(.nothingToDo(step)); continue
                }
                let ok = await Self.bounded(timedOut: false) { [inviteInbox] in await inviteInbox.disarm() }
                report.record(.single(step, succeeded: ok))

            case .cloudVault:
                guard CloudSyncService.isConfigured else { report.record(.nothingToDo(step)); continue }
                let ok = await Self.bounded(timedOut: false) { [cloudSync] in await cloudSync.eraseRemote() }
                report.record(.single(step, succeeded: ok))
            }
        }
        return report
    }

    /// Run `work` under `eraseStepBudget`, yielding `timedOut` if the budget
    /// runs out first. The losing child is cancelled, which is what actually
    /// unblocks a stalled URLSession or CloudKit request.
    private static func bounded<T: Sendable>(
        timedOut: T,
        _ work: @escaping @Sendable () async -> T
    ) async -> T {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { .some(await work()) }
            group.addTask {
                try? await Task.sleep(for: Self.eraseStepBudget)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? timedOut
        }
    }

    /// One-shot flag: RootView presents the "this device was signed out" alert once
    /// the erase below lands the user on onboarding.
    var remoteSignOutNotice = false
    private var remoteSignOutHandled = false

    /// A remote "Log Out Device" marker was found for THIS device (see
    /// `DeviceRegistryService`): erase LOCAL state only — the vault lives on in
    /// iCloud and on the owner's other devices, so none of the remote teardown
    /// in `tearDownRemoteState` may run — retire this device's registry identity so a
    /// future re-pair isn't wiped by the same marker, and land on onboarding.
    func handleRemoteSignOut() {
        guard !remoteSignOutHandled else { return }
        remoteSignOutHandled = true
        // Best-effort: remove our registry row while credentials still work.
        let registry = DeviceRegistryService(settings: settings)
        Task { await registry.deleteOwnRecord() }
        // Same reasoning as a local erase: nothing remote was revoked here, so
        // the quick-link tokens this device holds stay the only way to kill
        // links it created.
        eraseLocalState(retainingLinkRecords: liveQuickLinks)
        DeviceRegistryService.resetIdentityAfterRemoteSignOut()
        remoteSignOutNotice = true
    }

    /// The device-local portion of a vault erase, shared by all three ways in:
    /// "Erase on this device", the tail of "Erase everywhere" once the remote
    /// teardown has reported, and a remote sign-out (which must never tear down
    /// remote state — the vault lives on elsewhere).
    private func eraseLocalState(retainingLinkRecords retained: [LooxLinkRecord]) {
        sharingStore.wipe()
        // A quick link outlives the vault by up to its expiry, and its revoke
        // token is the ONLY credential that can kill it — deleting the token
        // with the vault leaves readable ciphertext nobody can ever revoke.
        // Links that are still live keep their token; everything else goes.
        looxLinks.records.wipe(keeping: retained)
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
        // Rendezvous inbox id + answered-invite ids. Cleared here even when the
        // remote descriptor could not be deleted, so no local residue names the
        // erased vault's inbox.
        InviteInboxService.clearLocalState()
        DeviceRegistryMirror.clear()
        settings.approvalModeEnabled = false
        settings.iCloudSyncEnabled = false
        repository.clear()
        artifactStore.eraseAll()
        // Sealed attachment blobs: unreadable once the Vault Key is gone, but a
        // directory of sized, timestamped files is still a record the vault
        // existed and how much was in it.
        attachmentStore.eraseAll()
        // Favicon cache filenames are a plaintext inventory of the sites the
        // erased vault held logins for.
        faviconService.clearCache()
        try? store.eraseAll()
        uiState.wipe()
        session.resetVault()
    }
}
