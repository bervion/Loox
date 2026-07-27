import CloudKit
import Foundation

/// Owner-side off-sheet refresh of outgoing share lifecycle.
///
/// The share sheet's own poll (`ShareAccessSheet.pollForProfile`) runs only
/// while the waiting screen is on-screen and is bounded to ~10 minutes; once
/// the owner dismisses the sheet or the app is relaunched, nothing re-checks
/// whether the recipient accepted. This pass fills that gap: on foreground and
/// on unlock it re-resolves every unconfirmed share's status and advances the
/// persisted `ShareLifecycle`, so an acceptance that landed after the sheet
/// closed still surfaces (in the config "Shared with" row today, in the
/// Notifications screen next).
///
/// Gated on `approvalModeEnabled` (never `iCloudSyncEnabled`, ADR-2). Reads only
/// public/ciphertext CloudKit metadata — no vault key, no plaintext. Single-
/// flighted to coalesce the foreground + unlock triggers that fire back-to-back.
@MainActor final class OwnerShareRefresher {
    private let store: SharingStore
    private let shareService: ApprovalShareService
    private let settings: SettingsStore
    private let notifier: ShareStatusNotifier
    /// Finishes a ready share without the owner: the scope was authorized at
    /// create time, so a profile landing is enough to publish.
    private let activation: ShareActivationService
    private let singleFlight = SingleFlight()
    private var observers: [NSObjectProtocol] = []
    /// One best-effort pass per process lifetime that installs the silent
    /// acceptance subscription onto in-flight shares created before that
    /// subscription existed. Failures simply retry on the next launch.
    private var subscriptionsBackfilled = false

    init(store: SharingStore, shareService: ApprovalShareService,
         settings: SettingsStore, notifier: ShareStatusNotifier,
         activation: ShareActivationService) {
        self.store = store
        self.shareService = shareService
        self.settings = settings
        self.notifier = notifier
        self.activation = activation
        // The recipient's device published its profile (silent push): resolve
        // the new status now instead of waiting for the next foreground pass.
        observers.append(NotificationCenter.default.addObserver(
            forName: .shareAcceptanceHint, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        })
    }

    /// Fire-and-forget: re-resolve status for all in-flight shares. Cheap — only
    /// unconfirmed records are touched, and the store's monotonic guard drops
    /// any downgrade from a transient miss.
    func refresh() {
        guard settings.approvalModeEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.refreshAndWait()
        }
    }

    /// Awaitable variant for the background silent-push path: the push
    /// delegate must not return its fetch completion handler while the
    /// CloudKit refresh is still running — iOS may suspend the process
    /// mid-fetch, the "accepted" banner silently never posts, and nothing
    /// retries until the next foreground. Returns only after a full refresh
    /// pass has completed (SingleFlight makes joining an in-flight run wait
    /// for it plus its follow-up).
    func refreshAndWait() async {
        guard settings.approvalModeEnabled else { return }
        await singleFlight.run { await self.refreshAll() }
    }

    private func refreshAll() async {
        let pending = store.shares.filter { !$0.fingerprintConfirmed }
        ShareDiagnostics.log("OWNER", "refresh: \(pending.count) unconfirmed share(s)")
        if !subscriptionsBackfilled {
            subscriptionsBackfilled = true
            for record in pending {
                try? await shareService.saveAcceptanceSubscription(
                    zoneID: CKRecordZone.ID(zoneName: record.zoneName))
            }
        }
        for record in pending {
            let zoneID = CKRecordZone.ID(zoneName: record.zoneName)
            let previous = record.status
            let next = await resolveStatus(zoneID: zoneID)
            ShareDiagnostics.log("OWNER", "share \(record.zoneName) → \(next)")
            store.updateStatus(zoneName: record.zoneName, to: next)
            guard next == .readyForCeremony else { continue }
            // The recipient's key has landed, and the owner already authorized
            // the scope when they created the invite — so finish the share here
            // rather than sending them back into the sheet to re-state a
            // decision they have already made.
            switch await activation.activate(record: record) {
            case .activated:
                notifier.notifyShareActive(record: record)
            case .needsUnlock, .needsOwnerScope, .failed:
                // Locked vault (sealing needs the live key), a record written
                // before scope was persisted, or a transient publish failure —
                // all resolve with the owner present, so fall back to the
                // banner that brings them in. `.readyForCeremony` stays
                // persisted, and the next unlock retries.
                if ShareStatusNotifier.shouldNotify(previous: previous, next: next,
                                                    appActive: notifier.isAppActive) {
                    notifier.notifyReadyForCeremony(record: record)
                }
            case .notReady:
                break
            }
        }
    }

    /// Profile-ready outranks accepted outranks invite-sent. A published profile
    /// implies acceptance, so try the profile fetch first and skip the extra
    /// share fetch when it succeeds.
    private func resolveStatus(zoneID: CKRecordZone.ID) async -> ShareLifecycle {
        if (try? await shareService.fetchParticipantProfile(zoneID: zoneID)) != nil {
            return .readyForCeremony
        }
        if await shareService.participantAccepted(zoneID: zoneID) {
            return .accepted
        }
        return .inviteSent
    }
}
