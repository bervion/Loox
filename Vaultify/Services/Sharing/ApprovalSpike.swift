#if DEBUG
import CloudKit
import Foundation

/// THROWAWAY Phase-1 gating spike — delete after the latency gate verdict is
/// recorded. Proves, across two real iCloud accounts, that:
/// 1. a looked-up participant (`.readWrite`) can WRITE a request record into
///    the owner's shared approval zone,
/// 2. the owner's zone ALERT subscription fires on that participant write,
/// 3. the owner's response reaches the requester via the shared-db push.
/// Logs `T_transport` / `T_roundtrip` / `TOTP_remaining` to
/// Documents/approval-spike-log.txt (console capture is unreliable here).
///
/// No crypto, no per-field config, no real TOTP — timing skeleton only. The
/// dummy code is "generated" at the APPROVE tap (not at request receipt) to
/// mirror the real foreground ceremony's timing.
@MainActor @Observable final class ApprovalSpike {
    static let shared = ApprovalSpike()

    private(set) var status = "idle"
    private(set) var shareURL: URL?

    /// Injected on flow entry (spike + its push observers are gated by
    /// `approvalModeEnabled`, never by `iCloudSyncEnabled` — plan step 7).
    @ObservationIgnored private var settings: SettingsStore?

    @ObservationIgnored private lazy var container = CKContainer(identifier: ApprovalConfig.containerID)
    private let zoneNameKey = "approval_spike_zone_name"
    private let sharedSubscription = SharedZoneSubscriptionService()
    private var observers: [NSObjectProtocol] = []

    /// Owner: pending request awaiting the human "Approve" tap.
    private var pendingRequest: CKRecord?
    /// Requester: commit time of the in-flight request (B clock — the clean
    /// same-clock baseline for `T_roundtrip`).
    private var requestCommittedAt: Date?
    private var requestRecordName: String?

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .approvalRequestReceived, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { _ = Task { await ApprovalSpike.shared.ownerFetchRequest() } }
        })
        observers.append(center.addObserver(forName: .approvalResponseReceived, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { _ = Task { await ApprovalSpike.shared.requesterFetchResponse() } }
        })
        observers.append(center.addObserver(forName: .vaultShareAccepted, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ApprovalSpike.shared.status = "share accepted — tap Send Request" }
        })
    }

    // MARK: Owner side

    /// Create opaque zone + CKShare restricted to a looked-up participant
    /// (programmatic add — no UICloudSharingController, publicPermission .none),
    /// plus the alert subscription that fires on participant writes.
    func startOwner(participantEmail: String, settings: SettingsStore) async {
        // CloudKit throws an uncatchable NSException (not a Swift error) on an
        // empty lookup email — validate BEFORE touching the API.
        let email = participantEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else {
            status = "enter the participant's iCloud email first"; return
        }
        if let blocker = await ApprovalPrerequisites.check() {
            status = "blocked: \(blocker)"; return
        }
        // Entering the sharing flow activates Approval Mode (its own flag —
        // deliberately NOT `iCloudSyncEnabled`).
        settings.approvalModeEnabled = true
        self.settings = settings
        do {
            let zoneName = UserDefaults.standard.string(forKey: zoneNameKey) ?? ApprovalConfig.opaqueZoneName()
            UserDefaults.standard.set(zoneName, forKey: zoneNameKey)
            let zoneID = CKRecordZone.ID(zoneName: zoneName)
            _ = try await container.privateCloudDatabase
                .modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

            // Fetch-or-create: a re-run must reuse the server's existing
            // zone-wide share (saving a fresh CKShare on an already-shared
            // zone fails with "record to insert already exists").
            let share = (try? await fetchShare(zoneID: zoneID)) ?? CKShare(recordZoneID: zoneID)
            share.publicPermission = .none
            let alreadyAdded = share.participants.contains {
                $0.userIdentity.lookupInfo?.emailAddress?.lowercased() == email.lowercased()
            }
            if !alreadyAdded {
                let participant = try await container.shareParticipant(forEmailAddress: email)
                participant.permission = .readWrite
                share.addParticipant(participant)
            }
            let saved = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
            for (_, result) in saved.saveResults { _ = try result.get() }

            try await saveOwnerAlertSubscription(zoneID: zoneID)
            shareURL = (try? await fetchShare(zoneID: zoneID))?.url ?? share.url
            status = "owner ready — send the share link to the participant"
            log("OWNER ready zone=\(zoneName)")
        } catch {
            status = "owner setup failed: \(error.localizedDescription)"
            log("OWNER setup error: \(error)")
        }
    }

    /// Owner clean-slate: delete the spike zone (drops the share + all spike
    /// records server-side) and its alert subscription, forget the zone name.
    func resetOwner() async {
        guard let zoneName = UserDefaults.standard.string(forKey: zoneNameKey) else {
            status = "nothing to reset"; return
        }
        do {
            _ = try await container.privateCloudDatabase
                .modifyRecordZones(saving: [], deleting: [CKRecordZone.ID(zoneName: zoneName)])
            _ = try? await container.privateCloudDatabase.modifySubscriptions(
                saving: [], deleting: [ApprovalConfig.requestSubscriptionID(zoneName: zoneName)])
            UserDefaults.standard.removeObject(forKey: zoneNameKey)
            shareURL = nil
            pendingRequest = nil
            status = "owner spike reset — run step 1 again"
            log("OWNER reset zone=\(zoneName)")
        } catch {
            status = "reset failed: \(error.localizedDescription)"
            log("OWNER reset error: \(error)")
        }
    }

    /// ALERT (user-visible) zone subscription — the whole point of ADR-5.
    /// Static copy only: no item, account, or code in the push.
    private func saveOwnerAlertSubscription(zoneID: CKRecordZone.ID) async throws {
        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: ApprovalConfig.requestSubscriptionID(zoneName: zoneID.zoneName))
        let info = CKSubscription.NotificationInfo()
        info.title = "Approval request"
        info.alertBody = "Someone is asking for a code. Open Loox to review."
        info.soundName = "default"
        subscription.notificationInfo = info
        _ = try await container.privateCloudDatabase
            .modifySubscriptions(saving: [subscription], deleting: [])
    }

    private func fetchShare(zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        return try await container.privateCloudDatabase.record(for: id) as? CKShare
    }

    /// Alert push (or tap) arrived → pull the newest request from the zone.
    private func ownerFetchRequest() async {
        guard settings?.approvalModeEnabled == true else { return }
        guard let zoneName = UserDefaults.standard.string(forKey: zoneNameKey) else { return }
        let receivedAt = Date()
        do {
            let records = try await fetchAll(ApprovalConfig.requestRecordType,
                                             database: container.privateCloudDatabase,
                                             zoneID: CKRecordZone.ID(zoneName: zoneName))
            guard let latest = records.max(by: { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }) else { return }
            pendingRequest = latest
            let requestedAt = latest["requestedAt"] as? Date ?? .distantPast
            // Cross-device clocks (NTP keeps skew ~sub-second between iPhones);
            // raw timestamps are logged so skew can be reasoned about later.
            let tTransport = receivedAt.timeIntervalSince(requestedAt)
            status = String(format: "request in — T_transport≈%.1fs — tap Approve", tTransport)
            log(String(format: "OWNER request received T_transport=%.2fs requestedAt=%@ receivedAt=%@ server=%@",
                       tTransport, iso(requestedAt), iso(receivedAt), iso(latest.creationDate ?? .distantPast)))
        } catch {
            log("OWNER fetch request error: \(error)")
        }
    }

    /// The human "Approve" tap — the dummy code's remaining lifetime starts HERE.
    func approvePending() async {
        guard let request = pendingRequest, let zoneID = request.recordID.zoneID as CKRecordZone.ID? else {
            status = "no pending request"; return
        }
        let approvedAt = Date()
        let remaining = 30 - approvedAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 30)
        let response = CKRecord(
            recordType: ApprovalConfig.responseRecordType,
            recordID: CKRecord.ID(recordName: ApprovalConfig.opaqueName(), zoneID: zoneID))
        response["requestName"] = request.recordID.recordName as CKRecordValue
        response["approvedAt"] = approvedAt as CKRecordValue
        response["remainingAtApproval"] = remaining as CKRecordValue
        do {
            let saved = try await container.privateCloudDatabase.modifyRecords(saving: [response], deleting: [])
            for (_, result) in saved.saveResults { _ = try result.get() }
            pendingRequest = nil
            status = String(format: "approved (%.0fs of code life left at approval)", remaining)
            log(String(format: "OWNER approved approvedAt=%@ remaining=%.1fs", iso(approvedAt), remaining))
        } catch {
            status = "approve failed: \(error.localizedDescription)"
            log("OWNER approve error: \(error)")
        }
    }

    // MARK: Requester side

    /// Write a dummy request into the accepted shared zone (proves participant
    /// `.readWrite` create) and arm the shared-db silent subscription.
    func sendRequest(settings: SettingsStore) async {
        settings.approvalModeEnabled = true
        self.settings = settings
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else { status = "blocked: iCloud unavailable"; return }
            await sharedSubscription.ensureSubscribedIfNeeded(settings: settings)
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            guard let zone = zones.first(where: { $0.zoneID.zoneName.hasPrefix(ApprovalConfig.zonePrefix) }) else {
                status = "no shared approval zone — accept the share link first"; return
            }
            let record = CKRecord(
                recordType: ApprovalConfig.requestRecordType,
                recordID: CKRecord.ID(recordName: ApprovalConfig.opaqueName(), zoneID: zone.zoneID))
            record["requestedAt"] = Date() as CKRecordValue
            let saved = try await container.sharedCloudDatabase.modifyRecords(saving: [record], deleting: [])
            for (_, result) in saved.saveResults { _ = try result.get() }
            requestCommittedAt = Date()
            requestRecordName = record.recordID.recordName
            status = "request committed — waiting for owner approval"
            log("REQUESTER committed request at \(iso(requestCommittedAt!)) (participant write OK)")
        } catch {
            status = "request failed: \(error.localizedDescription)"
            log("REQUESTER request error: \(error)")
        }
    }

    /// Shared-db push arrived → pull the response, compute the gate metrics.
    private func requesterFetchResponse() async {
        guard settings?.approvalModeEnabled == true else { return }
        guard let committedAt = requestCommittedAt, let requestName = requestRecordName else { return }
        let receivedAt = Date()
        do {
            let zones = try await container.sharedCloudDatabase.allRecordZones()
            guard let zone = zones.first(where: { $0.zoneID.zoneName.hasPrefix(ApprovalConfig.zonePrefix) }) else { return }
            let responses = try await fetchAll(ApprovalConfig.responseRecordType,
                                               database: container.sharedCloudDatabase,
                                               zoneID: zone.zoneID)
            guard let response = responses.first(where: { ($0["requestName"] as? String) == requestName }) else { return }
            let tRoundtrip = receivedAt.timeIntervalSince(committedAt) // same clock — clean
            let approvedAt = response["approvedAt"] as? Date ?? .distantPast
            let remainingAtApproval = response["remainingAtApproval"] as? Double ?? 0
            let totpRemaining = remainingAtApproval - receivedAt.timeIntervalSince(approvedAt)
            requestCommittedAt = nil
            status = String(format: "DONE — T_roundtrip=%.1fs, TOTP_remaining=%.1fs", tRoundtrip, totpRemaining)
            log(String(format: "REQUESTER response T_roundtrip=%.2fs TOTP_remaining=%.2fs approvedAt=%@ receivedAt=%@",
                       tRoundtrip, totpRemaining, iso(approvedAt), iso(receivedAt)))
        } catch {
            log("REQUESTER fetch response error: \(error)")
        }
    }

    // MARK: Helpers

    /// Full zone refetch (no delta cursor) — a spike zone holds a handful of
    /// records; delta tokens are transport-phase work.
    private func fetchAll(_ recordType: String, database: CKDatabase,
                          zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        var results: [CKRecord] = []
        var token: CKServerChangeToken?
        while true {
            let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            for (_, result) in changes.modificationResultsByID {
                if case .success(let modification) = result,
                   modification.record.recordType == recordType {
                    results.append(modification.record)
                }
            }
            token = changes.changeToken
            guard changes.moreComing else { return results }
        }
    }

    private func iso(_ date: Date) -> String {
        date.formatted(.iso8601.timeSeparator(.colon))
    }

    /// File-based log (Documents) — retrievable via `simctl get_app_container`
    /// or the Files app; stdout capture is unreliable in this environment.
    private func log(_ line: String) {
        let url = URL.documentsDirectory.appending(path: "approval-spike-log.txt")
        let entry = "\(iso(Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: url)
        }
    }
}
#endif
