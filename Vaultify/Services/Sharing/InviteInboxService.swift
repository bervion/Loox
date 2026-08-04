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
@MainActor @Observable final class InviteInboxService {
    @ObservationIgnored private lazy var container = CKContainer(identifier: ApprovalConfig.containerID)
    private var publicDB: CKDatabase { container.publicCloudDatabase }

    #if DEBUG
    /// In-app QA trace (the app has no Files-app sharing, so a Documents log
    /// is invisible to the tester) — newest last, capped.
    private(set) var debugLines: [String] = []
    #endif

    private static let inboxIDKey = "invite_inbox_id_v1"
    private static let seenInvitesKey = "invite_inbox_seen_ids_v1"
    /// Lifetime pinned to the U9 maximum, matching the link-invite tier.
    private static let dropLifetimeMs = InviteEnvelope.maxLifetimeMs

    /// Succeeded-this-launch latch — a FAILED arm retries on the next pass.
    private var armedThisLaunch = false
    /// Concurrent triggers (launch + foreground + push) must not stack a
    /// full arm sequence each — one in flight at a time.
    private var armInFlight = false

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
        guard CloudSyncService.isConfigured, !armedThisLaunch, !armInFlight else { return }
        armInFlight = true
        defer { armInFlight = false }
        do {
            guard try await container.accountStatus() == .available else { return }
            // A pure recipient has never been through the owner-side flow, so
            // this is the first place notification permission can be asked —
            // the alert push IS the auto-invite tier. Arm proceeds even when
            // denied (reconcile-on-open still works, pushes just won't show).
            // `check()` itself no longer prompts, so fire the request here.
            if await ApprovalPrerequisites.check() == .notificationsNotAsked {
                _ = await ApprovalPrerequisites.requestNotificationPermission()
            }
            let userID = try await container.userRecordID()
            let inboxID = Self.storedOrNewInboxID()

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

            // JIT-schema bootstrap: the subscription predicate references
            // `recipientInboxID`, which must exist on LooxInvite BEFORE the
            // subscription can be saved — link-tier records never carried the
            // field, so a fresh container rejects the predicate. A create +
            // delete of a dummy drop materializes it (Development only;
            // harmless no-op once the schema is deployed to Production).
            let bootstrap = CKRecord(recordType: ApprovalConfig.publicInviteRecordType,
                                     recordID: CKRecord.ID(recordName: "drop-" + ApprovalConfig.opaqueName()))
            bootstrap[Field.recipientInboxID] = "schema-bootstrap" as CKRecordValue
            bootstrap[Field.blob] = Data() as CKRecordValue
            bootstrap[Field.sentAtMs] = Int64(0) as CKRecordValue
            bootstrap[Field.expiresAtMs] = Int64(0) as CKRecordValue
            _ = try await publicDB.modifyRecords(saving: [bootstrap], deleting: [])
            _ = try? await publicDB.modifyRecords(saving: [], deleting: [bootstrap.recordID])

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
            debugLog("armed inbox=\(inboxID.prefix(8))… descriptor=inbox-\(userID.recordName)")
        } catch {
            // Best-effort — retried on the next launch/foreground pass (U6).
            debugLog("arm FAILED: \(error)")
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
            debugLog("reconcile FAILED: \(error)")
        }
        if !discovered.isEmpty { debugLog("reconcile found \(discovered.count) new invite(s)") }
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

    /// Whether this device ever published a rendezvous inbox. The erase path
    /// skips the teardown entirely when it did not, so an erase is never
    /// blocked by a step with nothing to tear down.
    static var hasPublishedInbox: Bool {
        UserDefaults.standard.string(forKey: inboxIDKey) != nil
    }

    /// Device-local rendezvous state: the inbox id and the answered-invite ids.
    /// Cleared by an erase even when the public descriptor could not be deleted,
    /// so nothing local keeps naming the erased vault's inbox.
    static func clearLocalState() {
        UserDefaults.standard.removeObject(forKey: inboxIDKey)
        UserDefaults.standard.removeObject(forKey: seenInvitesKey)
    }

    /// Erase-path teardown: public descriptor + subscription, then local state.
    /// Returns whether the descriptor is really gone.
    ///
    /// The remote delete runs FIRST and the local id is cleared only on success:
    /// dropping the id while the descriptor survives orphans a public record
    /// this device can no longer address, and re-arming mints a second one.
    @discardableResult
    func disarm() async -> Bool {
        armedThisLaunch = false
        guard Self.hasPublishedInbox else { return true }
        guard CloudSyncService.isConfigured, !CloudSyncService.isHostingUnitTests else {
            Self.clearLocalState()
            return true
        }
        guard let userID = try? await container.userRecordID() else { return false }
        do {
            _ = try await publicDB.modifyRecords(
                saving: [], deleting: [CKRecord.ID(recordName: "inbox-" + userID.recordName)])
        } catch {
            return false
        }
        _ = try? await publicDB.modifySubscriptions(
            saving: [], deleting: [ApprovalConfig.inviteInboxSubscriptionID])
        Self.clearLocalState()
        return true
    }

    // MARK: Sender side

    /// Best-effort auto-invite: nil when the recipient can't be resolved or
    /// has no armed inbox (U5 fallback = the link tier) — the caller always
    /// still offers the manual link. Returns the drop's record name for GC
    /// at activation/revoke (creator-only delete).
    ///
    /// `knownRecipientZoneNames`: this owner's approval zones for the SAME
    /// recipient — an email lookup deliberately returns NO userRecordID
    /// before any acceptance (anti-enumeration, verified on-device), so the
    /// opaque id comes from a share the recipient already accepted. Net: the
    /// FIRST invite to a person rides the link; repeats are automatic.
    func dropInvite(shareURL: URL, recipientEmail: String,
                    knownRecipientZoneNames: [String]) async -> String? {
        do {
            guard let target = await resolveRecipientInbox(
                email: recipientEmail, knownZoneNames: knownRecipientZoneNames) else {
                return nil
            }
            let signer = try DeviceSigningIdentity.loadOrCreate()
            let myID = try await container.userRecordID()
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let envelope = InviteEnvelope(
                inviteID: ApprovalConfig.opaqueName(),
                shareURL: shareURL.absoluteString,
                ownerParticipantID: myID.recordName,
                recipientParticipantID: target.recipientParticipantID,
                senderSigningPubKey: signer.publicKeyRaw,
                createdAtUnixMs: nowMs,
                expiresAtUnixMs: nowMs + Self.dropLifetimeMs)
            let blob = try envelope.sealedAndSigned(toRecipientPubKey: target.encryptionKey,
                                                    inboxID: target.inboxID, signer: signer)

            let drop = CKRecord(recordType: ApprovalConfig.publicInviteRecordType,
                                recordID: CKRecord.ID(recordName: "drop-" + ApprovalConfig.opaqueName()))
            drop[Field.recipientInboxID] = target.inboxID as CKRecordValue
            drop[Field.blob] = blob as CKRecordValue
            // Coarse (hour) timestamps — exact mint time is a needless leak;
            // the precise createdAt lives INSIDE the sealed envelope.
            drop[Field.sentAtMs] = ((nowMs / 3_600_000) * 3_600_000) as CKRecordValue
            drop[Field.expiresAtMs] = (((nowMs + Self.dropLifetimeMs) / 3_600_000) * 3_600_000) as CKRecordValue
            let saved = try await publicDB.modifyRecords(saving: [drop], deleting: [])
            for (_, result) in saved.saveResults { _ = try result.get() }
            debugLog("drop committed \(drop.recordID.recordName) → inbox \(target.inboxID.prefix(8))…")
            return drop.recordID.recordName
        } catch {
            debugLog("drop FAILED: \(error)")
            return nil
        }
    }

    /// Everything a drop needs about the recipient. Two channels, both
    /// post-acceptance (CloudKit hides userRecordID from email lookups):
    /// 1. The participant PROFILE the recipient published into one of this
    ///    owner's zones — carries inboxID + encryption key + the recipient's
    ///    self-declared userRecordID. Authoritative, no public-db hop.
    /// 2. Legacy: accepted-participant scan → public descriptor fetch (for
    ///    profiles written before the rendezvous fields existed).
    /// Net either way: FIRST invite rides the link; repeats are automatic.
    private func resolveRecipientInbox(email: String, knownZoneNames: [String]) async
        -> (inboxID: String, encryptionKey: Data, recipientParticipantID: String)? {
        let privateDB = container.privateCloudDatabase
        var sawProfileWithoutPointers = false
        for zoneName in knownZoneNames {
            let profileID = CKRecord.ID(
                recordName: ApprovalConfig.participantProfileRecordName,
                zoneID: CKRecordZone.ID(zoneName: zoneName))
            guard let profile = try? await privateDB.record(for: profileID) else { continue }
            if let inboxID = profile[ApprovalRecordMapping.Field.inviteInboxID] as? String,
               let recipientID = profile[ApprovalRecordMapping.Field.inviteRecipientID] as? String,
               let key = profile[ApprovalRecordMapping.Field.participantPubKey] as? Data {
                return (inboxID, key, recipientID)
            }
            // Profile predates the rendezvous pointers — B republishes them
            // the next time it opens Shared with Me / accepts on a new build.
            sawProfileWithoutPointers = true
        }

        guard let recipientID = await resolveRecipientUserRecordID(
            email: email, knownZoneNames: knownZoneNames) else {
            debugLog("drop skipped: unresolvable — scanned \(knownZoneNames.count) zone(s)"
                     + (sawProfileWithoutPointers
                        ? ", profile found WITHOUT pointers (B must open Shared with Me on the new build)"
                        : ", no accepted pairing yet — first invite rides the link"))
            return nil
        }
        guard let descriptor = try? await publicDB.record(
            for: CKRecord.ID(recordName: "inbox-" + recipientID.recordName)),
              let inboxID = descriptor[Field.inboxID] as? String,
              let encryptionKey = descriptor[Field.encryptionKey] as? Data else {
            debugLog("drop skipped: recipient has no inbox descriptor yet")
            return nil
        }
        return (inboxID, encryptionKey, recipientID.recordName)
    }

    /// The recipient's opaque CloudKit userRecordID. Email lookup first (in
    /// case a future OS populates it), then the participant lists of shares
    /// this recipient ALREADY accepted — the only privacy-clean source.
    private func resolveRecipientUserRecordID(email: String,
                                              knownZoneNames: [String]) async -> CKRecord.ID? {
        if let participant = try? await container.shareParticipant(forEmailAddress: email),
           let id = participant.userIdentity.userRecordID {
            return id
        }
        let privateDB = container.privateCloudDatabase
        for zoneName in knownZoneNames {
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare,
                                      zoneID: CKRecordZone.ID(zoneName: zoneName))
            guard let share = try? await privateDB.record(for: shareID) as? CKShare else { continue }
            if let match = share.participants.first(where: {
                $0.acceptanceStatus == .accepted &&
                $0.userIdentity.lookupInfo?.emailAddress?.lowercased() == email.lowercased()
            }), let id = match.userIdentity.userRecordID {
                return id
            }
        }
        return nil
    }

    // MARK: Helpers

    /// 256-bit random inbox id (U5) — never derived from email or any PII.
    private static func randomInboxID() -> String {
        CryptoRandom.bytes(32).map { String(format: "%02x", $0) }.joined()
    }

    /// The device's inbox id, minted on first use — also embedded in the
    /// participant profile B publishes into each owner's zone, so owners can
    /// auto-invite this recipient again without any public-db lookup.
    static func storedOrNewInboxID() -> String {
        if let existing = UserDefaults.standard.string(forKey: inboxIDKey) { return existing }
        let fresh = randomInboxID()
        UserDefaults.standard.set(fresh, forKey: inboxIDKey)
        return fresh
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

    /// QA diagnostics (DEBUG only, surfaced by the Settings debug panel) —
    /// ciphertext and full ids never logged.
    private func debugLog(_ line: String) {
        #if DEBUG
        let stamp = Date().formatted(date: .omitted, time: .standard)
        debugLines.append("\(stamp) \(line)")
        if debugLines.count > 100 { debugLines.removeFirst(debugLines.count - 100) }
        #endif
    }
}

#if DEBUG
import UserNotifications

extension InviteInboxService {
    /// Manual re-arm from the debug panel (bypasses the once-per-launch latch).
    func rearm(identity: ParticipantIdentity) async {
        armedThisLaunch = false
        await ensureArmed(identity: identity)
    }

    /// Server-truth snapshot: every hop the auto-invite depends on, with the
    /// raw error text when a hop fails — pinpoints WHERE delivery breaks.
    func diagnose() async -> String {
        var lines: [String] = []
        do {
            let status = try await container.accountStatus()
            lines.append("iCloud account: \(status == .available ? "available" : "NOT available (\(status.rawValue))")")
        } catch { lines.append("iCloud account: ERROR \(error.localizedDescription)") }

        let notif = await UNUserNotificationCenter.current().notificationSettings()
        lines.append("notification permission: \(notif.authorizationStatus.debugLabel)")

        let inboxID = UserDefaults.standard.string(forKey: Self.inboxIDKey)
        lines.append("local inboxID: \(inboxID.map { String($0.prefix(8)) + "…" } ?? "NONE (never armed)")")

        if let userID = try? await container.userRecordID() {
            do {
                let descriptor = try await publicDB.record(
                    for: CKRecord.ID(recordName: "inbox-" + userID.recordName))
                let remote = descriptor[Field.inboxID] as? String
                let match = remote == inboxID ? "matches local" : "MISMATCH vs local"
                lines.append("descriptor on server: yes (\(match))")
            } catch {
                lines.append("descriptor on server: NO — \(error.localizedDescription)")
            }
        } else {
            lines.append("descriptor check skipped: no userRecordID")
        }

        do {
            let subs = try await publicDB.allSubscriptions()
            let ours = subs.contains { $0.subscriptionID == ApprovalConfig.inviteInboxSubscriptionID }
            lines.append("public-db subscription: \(ours ? "ARMED" : "MISSING") (total \(subs.count))")
        } catch { lines.append("subscription check: ERROR \(error.localizedDescription)") }

        if let inboxID {
            do {
                let query = CKQuery(recordType: ApprovalConfig.publicInviteRecordType,
                                    predicate: NSPredicate(format: "%K == %@",
                                                           Field.recipientInboxID, inboxID))
                let (results, _) = try await publicDB.records(matching: query)
                lines.append("drops waiting in inbox: \(results.count)")
            } catch { lines.append("inbox query: ERROR \(error.localizedDescription)") }
        }

        lines.append("--- recent activity ---")
        lines.append(contentsOf: debugLines.suffix(12))
        return lines.joined(separator: "\n")
    }
}

private extension UNAuthorizationStatus {
    var debugLabel: String {
        switch self {
        case .authorized: "authorized"
        case .denied: "DENIED"
        case .notDetermined: "not determined (never asked)"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }
}
#endif
