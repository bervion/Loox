#if DEBUG
import CloudKit
import Foundation

/// THROWAWAY V1.1 Phase-3 gating spike (U5 — Opaque Public Rendezvous).
/// Proves, across two real iCloud accounts, the transport the Phase-4
/// encrypted envelope will ride on:
/// 1. B publishes an inbox descriptor in the PUBLIC db keyed by its opaque
///    CloudKit userRecordID (never email/PII — U3) and arms a
///    `CKQuerySubscription(recipientInboxID == myInboxID)`.
/// 2. A resolves B's email → CK participant → userRecordID → descriptor →
///    inboxID, then drops a `LooxInvite` record addressed to that inbox.
/// 3. B's query-subscription push fires → B queries the inbox, logs latency,
///    deletes the drop (U9 delete-after-accept).
///
/// Answers the plan's spike questions: descriptor keying, public-db query
/// subscription fire-on-creation reliability (dev AND Production/TestFlight —
/// run there EARLY), locked-device behavior. No crypto — payload is a dummy;
/// sealing/signature/expiry/replay is Phase 4, gated on this transport.
/// Logs to Documents/rendezvous-spike-log.txt (console capture unreliable).
@MainActor @Observable final class InviteRendezvousSpike {
    static let shared = InviteRendezvousSpike()

    private(set) var status = "idle"

    @ObservationIgnored private lazy var container = CKContainer(identifier: ApprovalConfig.containerID)
    private var publicDB: CKDatabase { container.publicCloudDatabase }
    private let inboxIDKey = "invite_rendezvous_inbox_id"
    private var observers: [NSObjectProtocol] = []

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .inviteRendezvousReceived, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                _ = Task { await InviteRendezvousSpike.shared.fetchInvites(trigger: "push") }
            }
        })
    }

    // MARK: B side — arm inbox

    /// Publish descriptor + arm the query subscription. Idempotent (re-arm
    /// overwrites via `.allKeys`; same subscription id re-saves).
    func armInbox() async {
        do {
            guard try await container.accountStatus() == .available else {
                status = "blocked: iCloud unavailable"; return
            }
            let userID = try await container.userRecordID()
            let inboxID = UserDefaults.standard.string(forKey: inboxIDKey) ?? Self.randomInboxID()
            UserDefaults.standard.set(inboxID, forKey: inboxIDKey)

            // Descriptor keyed by the OPAQUE CK user record id — the inviter
            // reaches it by direct record fetch after participant lookup, so
            // the field itself never needs a queryable index.
            let descriptor = CKRecord(
                recordType: ApprovalConfig.inviteInboxDescriptorRecordType,
                recordID: CKRecord.ID(recordName: "inbox-" + userID.recordName))
            descriptor["inboxID"] = inboxID as CKRecordValue
            _ = try await publicDB.modifyRecords(saving: [descriptor], deleting: [],
                                                 savePolicy: .allKeys)

            // Dev-schema bootstrap: the subscription predicate references
            // `recipientInboxID`, which must exist on the LooxInvite type
            // before the subscription can be saved. A create+delete of a
            // dummy drop JIT-creates the field in the Development schema
            // (harmless no-op once the schema is deployed to Production).
            let bootstrap = CKRecord(recordType: ApprovalConfig.publicInviteRecordType,
                                     recordID: CKRecord.ID(recordName: "drop-" + ApprovalConfig.opaqueName()))
            bootstrap["recipientInboxID"] = "schema-bootstrap" as CKRecordValue
            bootstrap["sentAtMs"] = Int64(0) as CKRecordValue
            bootstrap["expiresAtMs"] = Int64(0) as CKRecordValue
            bootstrap["blob"] = Data() as CKRecordValue
            _ = try await publicDB.modifyRecords(saving: [bootstrap], deleting: [])
            _ = try? await publicDB.modifyRecords(saving: [], deleting: [bootstrap.recordID])

            let subscription = CKQuerySubscription(
                recordType: ApprovalConfig.publicInviteRecordType,
                predicate: NSPredicate(format: "recipientInboxID == %@", inboxID),
                subscriptionID: ApprovalConfig.inviteInboxSubscriptionID,
                options: [.firesOnRecordCreation])
            let info = CKSubscription.NotificationInfo()
            info.title = "Loox spike"
            info.alertBody = "Invite drop arrived (rendezvous spike)."
            info.soundName = "default"
            subscription.notificationInfo = info
            _ = try await publicDB.modifySubscriptions(saving: [subscription], deleting: [])

            status = "inbox armed — inboxID \(inboxID.prefix(8))…"
            log("B armed inbox=\(inboxID) descriptor=inbox-\(userID.recordName)")
        } catch {
            status = "arm failed: \(error.localizedDescription)"
            log("B arm error: \(error)")
        }
    }

    // MARK: A side — drop an invite

    /// Email → CK participant (SAME resolution the CKShare path uses) →
    /// opaque userRecordID → descriptor → inboxID → addressed public drop.
    /// Public db sees: opaque ids, dummy blob, timing. No email, no URL.
    func sendInvite(toEmail rawEmail: String) async {
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else { status = "enter B's iCloud email first"; return }
        do {
            let participant = try await container.shareParticipant(forEmailAddress: email)
            guard let recipientID = participant.userIdentity.userRecordID else {
                status = "participant resolved but no userRecordID"; return
            }
            let descriptorID = CKRecord.ID(recordName: "inbox-" + recipientID.recordName)
            guard let descriptor = try? await publicDB.record(for: descriptorID),
                  let inboxID = descriptor["inboxID"] as? String else {
                // The real feature's fallback tier: not a Loox user (or inbox
                // not armed) → external invite link instead.
                status = "B has no inbox descriptor — fallback would be the link invite"
                log("A drop aborted: no descriptor for \(recipientID.recordName)")
                return
            }
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let drop = CKRecord(recordType: ApprovalConfig.publicInviteRecordType,
                                recordID: CKRecord.ID(recordName: "drop-" + ApprovalConfig.opaqueName()))
            drop["recipientInboxID"] = inboxID as CKRecordValue
            drop["sentAtMs"] = nowMs as CKRecordValue
            drop["expiresAtMs"] = (nowMs + 24 * 3_600_000) as CKRecordValue
            drop["blob"] = Data("rendezvous-spike".utf8) as CKRecordValue
            _ = try await publicDB.modifyRecords(saving: [drop], deleting: [])
            status = "drop committed — watch device B (push should fire)"
            log("A drop committed inbox=\(inboxID.prefix(8))… at \(nowMs)")
        } catch {
            status = "drop failed: \(error.localizedDescription)"
            log("A drop error: \(error)")
        }
    }

    // MARK: B side — reconcile inbox (push = hint, query = truth)

    /// Manual "Fetch now" exists deliberately: U6 says a missed push must
    /// never mean a lost invite — the query IS the source of truth.
    func fetchInvites(trigger: String) async {
        guard let inboxID = UserDefaults.standard.string(forKey: inboxIDKey) else {
            status = "no inbox armed on this device"; return
        }
        let receivedAt = Date()
        do {
            let query = CKQuery(recordType: ApprovalConfig.publicInviteRecordType,
                                predicate: NSPredicate(format: "recipientInboxID == %@", inboxID))
            let (results, _) = try await publicDB.records(matching: query)
            var found = 0
            var lastLatency = 0.0
            for (recordID, result) in results {
                guard case .success(let record) = result else { continue }
                found += 1
                let sentAtMs = record["sentAtMs"] as? Int64 ?? 0
                // Cross-device clocks (NTP skew ~sub-second) — good enough
                // for a transport-latency gate reading.
                lastLatency = receivedAt.timeIntervalSince1970 - Double(sentAtMs) / 1000
                log(String(format: "B got drop trigger=%@ latency=%.2fs record=%@",
                           trigger, lastLatency, recordID.recordName))
                // U9: an invite is a bootstrap artifact — delete after pickup.
                _ = try? await publicDB.modifyRecords(saving: [], deleting: [recordID])
            }
            status = found == 0
                ? "inbox empty (trigger=\(trigger))"
                : String(format: "got %d drop(s) — latency %.1fs (trigger=%@)",
                         found, lastLatency, trigger)
        } catch {
            status = "fetch failed: \(error.localizedDescription)"
            log("B fetch error (trigger=\(trigger)): \(error)")
        }
    }

    // MARK: Reset

    /// Remove descriptor + subscription + local inbox id (both roles safe).
    func reset() async {
        do {
            let userID = try await container.userRecordID()
            _ = try? await publicDB.modifyRecords(
                saving: [], deleting: [CKRecord.ID(recordName: "inbox-" + userID.recordName)])
            _ = try? await publicDB.modifySubscriptions(
                saving: [], deleting: [ApprovalConfig.inviteInboxSubscriptionID])
            UserDefaults.standard.removeObject(forKey: inboxIDKey)
            status = "rendezvous spike reset"
            log("reset for \(userID.recordName)")
        } catch {
            status = "reset failed: \(error.localizedDescription)"
        }
    }

    // MARK: Helpers

    /// 256-bit random inbox id (U5): never derived from email or any PII.
    private static func randomInboxID() -> String {
        CryptoRandom.bytes(32).map { String(format: "%02x", $0) }.joined()
    }

    private func log(_ line: String) {
        let url = URL.documentsDirectory.appending(path: "rendezvous-spike-log.txt")
        let entry = "\(Date().formatted(.iso8601.timeSeparator(.colon))) \(line)\n"
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
