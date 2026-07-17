import CloudKit
import Foundation

/// Gates the owner-side request zone scan behind a dirty flag so foreground
/// and screen-appear triggers stop paging every record of every owned zone
/// when there is nothing new. A CKQuery for just the request records would
/// need queryable indexes deployed on the production CloudKit schema (a
/// missing index fails at runtime in prod only); the dirty flag needs zero
/// schema work and cuts steady-state scans to zero.
///
/// Contract:
/// - Starts dirty: pushes are best-effort, so the first pass per process
///   lifetime always scans (a request written while the app was dead would
///   otherwise be missed until the next push).
/// - A request push marks the gate dirty.
/// - A non-empty inbox always scans: the pass is what expires TTL'd entries
///   and drops records from revoked zones.
/// - Consume-then-restore: the flag is cleared BEFORE the scan starts so a
///   push landing mid-pass re-dirties it and survives the pass; a failed
///   (offline/transient) pass restores it so the next trigger retries.
nonisolated struct RequestScanGate {
    private(set) var isDirty = true

    /// A request push arrived; the next trigger must scan.
    mutating func markDirty() { isDirty = true }

    /// Whether a refresh trigger should run the zone scan at all.
    func shouldScan(inboxEmpty: Bool) -> Bool { isDirty || !inboxEmpty }

    /// Consume the flag as the scan starts (see contract above).
    mutating func beginScan() { isDirty = false }

    /// The scan hit an offline/transient error: restore the flag so the
    /// next trigger retries instead of silently going stale.
    mutating func scanFailed() { isDirty = true }
}

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
    /// True while the notifications screen is frontmost: the shell must not
    /// auto-present the ceremony sheet over it (the two presenters would
    /// fight and SwiftUI dismisses one) — rows there open it deliberately.
    var autoPresentSuppressed = false
    /// Monotonic signal for recipient-side observers (cheap invalidation).
    private(set) var recipientChangeCounter = 0
    /// Requests already answered or explicitly dismissed on this device.
    /// A responded request can outlive its record delete (offline, failed
    /// best-effort delete) yet still pass the PreviewNonceStore display
    /// verification — without this set it would re-enter the inbox and
    /// re-present its sheet until the record's TTL expires. Persisted so a
    /// relaunch inside that TTL window can't re-present it either.
    private static let handledKey = "approval_handled_request_ids"
    private var handledRequestIds: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: handledKey) ?? [])

    private let settings: SettingsStore
    private let shareService: ApprovalShareService
    private let singleFlight = SingleFlight()
    private var observers: [NSObjectProtocol] = []
    /// All reads/writes happen on the main actor (this class is @MainActor),
    /// so the gate needs no locking.
    private var scanGate = RequestScanGate()

    init(settings: SettingsStore, shareService: ApprovalShareService) {
        self.settings = settings
        self.shareService = shareService
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .approvalRequestReceived, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scanGate.markDirty()
                self?.refreshOwnerRequests()
            }
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
        guard scanGate.shouldScan(inboxEmpty: pendingOwnerRequests.isEmpty) else {
            ShareDiagnostics.log("OWNER", "request scan skipped (no push since last pass, inbox empty)")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await self.singleFlight.run {
                // Consume-then-restore: clear the flag up front so a push
                // arriving mid-pass re-dirties it and the next trigger
                // rescans (clearing after the loop would swallow it).
                self.scanGate.beginScan()
                var sawError = false
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
                        // Per-grant transport: one zone can hold several
                        // grants (one per item), each under its own record
                        // name — resolve every request against ITS grant by
                        // the authenticated `request.grantId`. A thrown fetch
                        // flows to the catches below (zone gone vs transient),
                        // exactly like the request fetch above.
                        let grants = try await self.shareService.fetchAllGrants(
                            zoneID: zoneID, nowUnixMs: nowUnixMs)
                        guard let ownerKey = try? DeviceSigningIdentity.loadOrCreate().publicKeyRaw
                        else { continue }
                        let grantsById = Dictionary(grants.map { ($0.id, $0) },
                                                    uniquingKeysWith: { _, newer in newer })
                        for request in live where !self.handledRequestIds.contains(request.requestId) {
                            guard let grant = grantsById[request.grantId] else { continue }
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
                        // Zone gone = share revoked/left; drop the registry
                        // entry. A successful determination, not a failure —
                        // it must not restore the dirty flag.
                        ApprovalShareService.unregisterZone(zoneName)
                    } catch {
                        // Offline/transient — keep whatever we already show
                        // and retry the scan on the next trigger.
                        sawError = true
                    }
                }
                if sawError { self.scanGate.scanFailed() }
                self.pendingOwnerRequests = collected
                    .sorted { $0.request.createdAtUnixMs > $1.request.createdAtUnixMs }
            }
        }
    }

    /// Drop a request from the inbox after the ceremony finished (approve,
    /// reject, dismiss) and suppress it from future refreshes — the record
    /// is deleted at respond (best-effort) or expires via its TTL, and a
    /// dismissed request must not re-nag; the requester's retry carries a
    /// NEW requestId, so nothing real is lost.
    func clearPending(requestId: String) {
        handledRequestIds.insert(requestId)
        // Bounded persist: ids only matter within the request TTL (~2 min),
        // so a small FIFO window is plenty.
        var stored = UserDefaults.standard.stringArray(forKey: Self.handledKey) ?? []
        stored.append(requestId)
        if stored.count > 100 { stored.removeFirst(stored.count - 100) }
        UserDefaults.standard.set(stored, forKey: Self.handledKey)
        pendingOwnerRequests.removeAll { $0.request.requestId == requestId }
    }

    private func bumpRecipientCounter() {
        guard settings.approvalModeEnabled else { return }
        recipientChangeCounter += 1
    }
}
