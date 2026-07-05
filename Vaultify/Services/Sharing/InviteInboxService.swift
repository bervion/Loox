import CloudKit
import CryptoKit
import Foundation

/// Loox-to-Loox auto-invite tier (U5 — A' Opaque Public Rendezvous).
///
/// Recipient: publishes an inbox descriptor in the PUBLIC db keyed by its
/// opaque CloudKit userRecordID (never email/PII — U3) and arms a query
/// subscription on drops addressed to its random 256-bit inboxID.
/// Sender: resolves email → CK participant → userRecordID → descriptor →
/// sealed `InviteEnvelope` drop. Public db sees opaque ids, ciphertext, and
/// coarse timing only. Push = hint; `reconcile` is the source of truth (U6).
///
/// Public-db records are deletable only by their CREATOR, so drop GC belongs
/// to the sender (at activation/revoke, like the link-invite record); the
/// recipient dedups by inviteID instead of deleting.
@MainActor final class InviteInboxService {
    private lazy var container = CKContainer(identifier: ApprovalConfig.containerID)
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    private static let inboxIDKey = "invite_inbox_id_v1"
    private static let seenInvitesKey = "invite_inbox_seen_ids_v1"
    /// Lifetime pinned to the U9 maximum, matching the link-invite tier.
    private static let dropLifetimeMs = InviteEnvelope.maxLifetimeMs

    /// Succeeded-this-launch latch — a FAILED arm retries on the next pass.
    private var armedThisLaunch = false

    private enum Field {
        static let inboxID = "inboxID"
        static let encryptionKey = "encryptionKey"
        static let signingKey = "signingKey"
        static let signature = "sig"
        static let recipientInboxID = "recipientInboxID"
        static let blob = "blob"
        static let sentAtMs = "sentAtMs"
        static let expiresAtMs = "expiresAtMs"
    }

    // MARK: Recipient side

    /// Publish the signed descriptor + arm the alert subscription. Idempotent:
    /// the inboxID is minted once and re-published (`.allKeys`), the
    /// subscription is replaced under its fixed id (delete-then-save —
    /// CloudKit can't morph an existing subscription's predicate in place).
    func ensureArmed(identity: ParticipantIdentity) async {
        guard CloudSyncService.isConfigured, !armedThisLaunch else { return }
        do {
            guard try await container.accountStatus() == .available else { return }
            let userID = try await container.userRecordID()
            let inboxID = UserDefaults.standard.string(forKey: Self.inboxIDKey)
                ?? Self.randomInboxID()
            UserDefaults.standard.set(inboxID, forKey: Self.inboxIDKey)

            let signer = try DeviceSigningIdentity.loadOrCreate()
            let descriptor = CKRecord(
                recordType: ApprovalConfig.inviteInboxDescriptorRecordType,
                recordID: CKRecord.ID(recordName: "inbox-" + userID.recordName))
            descriptor[Field.inboxID] = inboxID as CKRecordValue
            descriptor[Field.encryptionKey] = identity.publicKeyRaw as CKRecordValue
            descriptor[Field.signingKey] = signer.publicKeyRaw as CKRecordValue
            // Self-consistency signature (the ceremony, not this record,
            // decides whether the keys are ultimately trusted — U10).
            descriptor[Field.signature] = try signer.signature(
                for: Self.descriptorSigningBody(inboxID: inboxID,
                                                encryptionKey: identity.publicKeyRaw,
                                                signingKey: signer.publicKeyRaw)) as CKRecordValue
            _ = try await publicDB.modifyRecords(saving: [descriptor], deleting: [],
                                                 savePolicy: .allKeys)

            let subscription = CKQuerySubscription(
                recordType: ApprovalConfig.publicInviteRecordType,
                predicate: NSPredicate(format: "%K == %@", Field.recipientInboxID, inboxID),
                subscriptionID: ApprovalConfig.inviteInboxSubscriptionID,
                options: [.firesOnRecordCreation])
            let info = CKSubscription.NotificationInfo()
            info.titleLocalizationKey = "invite.push.title"
            info.alertLocalizationKey = "invite.push.body"
            info.soundName = "default"
            subscription.notificationInfo = info
            _ = try? await publicDB.modifySubscriptions(
                saving: [], deleting: [ApprovalConfig.inviteInboxSubscriptionID])
            _ = try await publicDB.modifySubscriptions(saving: [subscription], deleting: [])
            armedThisLaunch = true
        } catch {
            // Best-effort — retried on the next launch/foreground pass (U6).
        }
    }

    /// Pull every drop addressed to this inbox, open + dedup, return the new
    /// envelopes (oldest first). Bad/expired/replayed drops are dropped
    /// silently — fail-closed, no partial trust.
    ///
    /// Dedup is READ-only here: an invite becomes "seen" when the USER
    /// responds (`markSeen`), never at discovery — a lock/kill between
    /// discovery and response must not swallow the invite forever.
    func reconcile(identity: ParticipantIdentity) async -> [InviteEnvelope] {
        guard CloudSyncService.isConfigured,
              let inboxID = UserDefaults.standard.string(forKey: Self.inboxIDKey) else { return [] }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let seen = Set(UserDefaults.standard.stringArray(forKey: Self.seenInvitesKey) ?? [])
        var collected: Set<String> = []
        var discovered: [InviteEnvelope] = []
        do {
            let query = CKQuery(recordType: ApprovalConfig.publicInviteRecordType,
                                predicate: NSPredicate(format: "%K == %@",
                                                       Field.recipientInboxID, inboxID))
            let (results, _) = try await publicDB.records(matching: query)
            for (_, result) in results {
                guard case .success(let record) = result,
                      let blob = record[Field.blob] as? Data,
                      let envelope = try? InviteEnvelope.open(
                          blob, recipientPrivateKey: identity.privateKey,
                          inboxID: inboxID, nowUnixMs: nowMs),
                      !seen.contains(envelope.inviteID),
                      collected.insert(envelope.inviteID).inserted else { continue }
                discovered.append(envelope)
            }
        } catch {
            // Offline/transient — the next reconcile pass picks them up.
        }
        return discovered.sorted { $0.createdAtUnixMs < $1.createdAtUnixMs }
    }

    /// The user responded to this invite (accept OR dismiss) — never prompt
    /// for it again, across relaunches. True FIFO cap: oldest ids evicted
    /// first (their drops are long expired by then).
    func markSeen(inviteID: String) {
        var seen = UserDefaults.standard.stringArray(forKey: Self.seenInvitesKey) ?? []
        guard !seen.contains(inviteID) else { return }
        seen.append(inviteID)
        if seen.count > 200 { seen.removeFirst(seen.count - 200) }
        UserDefaults.standard.set(seen, forKey: Self.seenInvitesKey)
    }

    /// Erase-path teardown: descriptor + subscription + local state.
    func disarm() async {
        UserDefaults.standard.removeObject(forKey: Self.inboxIDKey)
        UserDefaults.standard.removeObject(forKey: Self.seenInvitesKey)
        armedThisLaunch = false
        if let userID = try? await container.userRecordID() {
            _ = try? await publicDB.modifyRecords(
                saving: [], deleting: [CKRecord.ID(recordName: "inbox-" + userID.recordName)])
        }
        _ = try? await publicDB.modifySubscriptions(
            saving: [], deleting: [ApprovalConfig.inviteInboxSubscriptionID])
    }

    // MARK: Sender side

    /// Best-effort auto-invite: nil when the recipient has no armed inbox
    /// (not a Loox user yet, U5 fallback = the link tier) or on any failure —
    /// the caller always still offers the manual link. Returns the drop's
    /// record name for GC at activation/revoke (creator-only delete).
    func dropInvite(shareURL: URL, recipientEmail: String) async -> String? {
        do {
            let participant = try await container.shareParticipant(forEmailAddress: recipientEmail)
            guard let recipientID = participant.userIdentity.userRecordID else { return nil }
            let descriptor = try await publicDB.record(
                for: CKRecord.ID(recordName: "inbox-" + recipientID.recordName))
            guard let inboxID = descriptor[Field.inboxID] as? String,
                  let encryptionKey = descriptor[Field.encryptionKey] as? Data else { return nil }

            let signer = try DeviceSigningIdentity.loadOrCreate()
            let myID = try await container.userRecordID()
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let envelope = InviteEnvelope(
                inviteID: ApprovalConfig.opaqueName(),
                shareURL: shareURL.absoluteString,
                ownerParticipantID: myID.recordName,
                recipientParticipantID: recipientID.recordName,
                senderSigningPubKey: signer.publicKeyRaw,
                createdAtUnixMs: nowMs,
                expiresAtUnixMs: nowMs + Self.dropLifetimeMs)
            let blob = try envelope.sealedAndSigned(toRecipientPubKey: encryptionKey,
                                                    inboxID: inboxID, signer: signer)

            let drop = CKRecord(recordType: ApprovalConfig.publicInviteRecordType,
                                recordID: CKRecord.ID(recordName: "drop-" + ApprovalConfig.opaqueName()))
            drop[Field.recipientInboxID] = inboxID as CKRecordValue
            drop[Field.blob] = blob as CKRecordValue
            // Coarse (hour) timestamps — exact mint time is a needless leak;
            // the precise createdAt lives INSIDE the sealed envelope.
            drop[Field.sentAtMs] = ((nowMs / 3_600_000) * 3_600_000) as CKRecordValue
            drop[Field.expiresAtMs] = (((nowMs + Self.dropLifetimeMs) / 3_600_000) * 3_600_000) as CKRecordValue
            let saved = try await publicDB.modifyRecords(saving: [drop], deleting: [])
            for (_, result) in saved.saveResults { _ = try result.get() }
            return drop.recordID.recordName
        } catch {
            return nil
        }
    }

    // MARK: Helpers

    /// 256-bit random inbox id (U5) — never derived from email or any PII.
    private static func randomInboxID() -> String {
        CryptoRandom.bytes(32).map { String(format: "%02x", $0) }.joined()
    }

    private static func descriptorSigningBody(inboxID: String, encryptionKey: Data,
                                              signingKey: Data) -> Data {
        var w = CanonicalWriter()
        w.string("Loox invite inbox v1")
        w.string(inboxID)
        w.blob(encryptionKey)
        w.blob(signingKey)
        return w.data
    }
}
