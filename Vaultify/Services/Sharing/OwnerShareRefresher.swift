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
    private let singleFlight = SingleFlight()

    init(store: SharingStore, shareService: ApprovalShareService, settings: SettingsStore) {
        self.store = store
        self.shareService = shareService
        self.settings = settings
    }

    /// Fire-and-forget: re-resolve status for all in-flight shares. Cheap — only
    /// unconfirmed records are touched, and the store's monotonic guard drops
    /// any downgrade from a transient miss.
    func refresh() {
        guard settings.approvalModeEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.singleFlight.run { await self.refreshAll() }
        }
    }

    private func refreshAll() async {
        for record in store.shares where !record.fingerprintConfirmed {
            let zoneID = CKRecordZone.ID(zoneName: record.zoneName)
            let next = await resolveStatus(zoneID: zoneID)
            store.updateStatus(zoneName: record.zoneName, to: next)
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
