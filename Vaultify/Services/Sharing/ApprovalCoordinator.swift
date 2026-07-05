import CloudKit
import Foundation

/// Reacts to the approval push pipeline (ADR-5) and refreshes control-plane
/// state — single-flighted, and gated by `approvalModeEnabled`, NEVER by
/// `iCloudSyncEnabled` (ADR-2: enabling approval sharing must not imply
/// vault-item sync, and vault-sync-off must not mute approvals).
///
/// Owner side: `.approvalRequestReceived` → pull live requests from every
/// owned approval zone into `pendingOwnerRequests` (the Phase-5 inbox).
/// Recipient side: `.approvalResponseReceived` / `.vaultShareAccepted` bump
/// `recipientChangeCounter`; the Phase-6 request state machine owns the
/// per-request fetch (it holds the in-memory ephemeral keys).
@MainActor @Observable final class ApprovalCoordinator {
    struct PendingOwnerRequest: Identifiable {
        var id: String { request.requestId }
        let zoneName: String
        let request: ApprovalRequest
    }

    private(set) var pendingOwnerRequests: [PendingOwnerRequest] = []
    /// Monotonic signal for recipient-side observers (cheap invalidation).
    private(set) var recipientChangeCounter = 0

    private let settings: SettingsStore
    private let shareService: ApprovalShareService
    private let singleFlight = SingleFlight()
    private var observers: [NSObjectProtocol] = []

    init(settings: SettingsStore, shareService: ApprovalShareService) {
        self.settings = settings
        self.shareService = shareService
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .approvalRequestReceived, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshOwnerRequests() }
        })
        observers.append(center.addObserver(
            forName: .approvalResponseReceived, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.bumpRecipientCounter() }
        })
        observers.append(center.addObserver(
            forName: .vaultShareAccepted, object: nil, queue: .main
        ) { [weak self] _ in
            // UNCONDITIONAL: a first-time recipient has approvalModeEnabled
            // still false — gating this bump would deadlock the acceptance
            // resume that is the very thing that turns the flag on.
            MainActor.assumeIsolated { self?.recipientChangeCounter += 1 }
        })
    }

    /// Also called on foreground/unlock so a missed push never strands a
    /// request (pushes are best-effort; the inbox is the source of truth).
    func refreshOwnerRequests() {
        guard settings.approvalModeEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.singleFlight.run {
                let nowUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
                var collected: [PendingOwnerRequest] = []
                for zoneName in ApprovalShareService.ownedZoneNames {
                    let zoneID = CKRecordZone.ID(zoneName: zoneName)
                    do {
                        let live = try await self.shareService.fetchLiveRequests(
                            zoneID: zoneID, nowUnixMs: nowUnixMs)
                        guard !live.isEmpty else { continue }
                        // Verify-before-show: only a request that passes the
                        // kernel checks reaches any UI. Display verification
                        // uses PreviewNonceStore — the single-use nonce burns
                        // only at approve, not at render.
                        guard let grant = try? await self.shareService.fetchGrantFresh(zoneID: zoneID),
                              let ownerKey = try? DeviceSigningIdentity.loadOrCreate().publicKeyRaw
                        else { continue }
                        for request in live {
                            let failure = await ApprovalVerifier.verifyRequest(
                                request, grant: grant,
                                trustedOwnerSigningKeys: [ownerKey],
                                currentEpoch: grant.epoch, nowUnixMs: nowUnixMs,
                                nonceStore: PreviewNonceStore())
                            if failure == nil {
                                collected.append(PendingOwnerRequest(zoneName: zoneName,
                                                                     request: request))
                            }
                        }
                    } catch let error as CKError
                        where error.code == .zoneNotFound || error.code == .userDeletedZone {
                        // Zone gone = share revoked/left; drop the registry entry.
                        ApprovalShareService.unregisterZone(zoneName)
                    } catch {
                        // Offline/transient — keep whatever we already show.
                    }
                }
                self.pendingOwnerRequests = collected
                    .sorted { $0.request.createdAtUnixMs > $1.request.createdAtUnixMs }
            }
        }
    }

    /// Drop a request from the inbox after the ceremony finished (approve,
    /// reject, dismiss) — the zone record expires server-side via its TTL.
    func clearPending(requestId: String) {
        pendingOwnerRequests.removeAll { $0.request.requestId == requestId }
    }

    private func bumpRecipientCounter() {
        guard settings.approvalModeEnabled else { return }
        recipientChangeCounter += 1
    }
}
