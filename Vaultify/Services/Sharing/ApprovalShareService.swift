import CloudKit
import CryptoKit
import Foundation

/// Owner-side (A) transport for Approval Mode: per-recipient opaque zone +
/// looked-up CKShare (ADR-4, no bearer semantics), grant + sealed-blob
/// publishing, request verification against a FRESH grant fetch, and signed
/// responses. All ciphertext/public data only — the control plane never
/// carries vault plaintext (ADR-2).
@MainActor final class ApprovalShareService {
    enum Failure: Error, LocalizedError {
        case invalidRecipientEmail
        case prerequisitesBlocked(ApprovalPrerequisites.Blocker)
        case noParticipantProfile
        case grantMissing
        case verifyFailed(ApprovalVerifyFailure)

        var errorDescription: String? {
            switch self {
            case .invalidRecipientEmail:
                return appString("Enter the recipient's iCloud email first.")
            case .prerequisitesBlocked:
                return appString("Sharing isn't available right now — check iCloud and notification permissions.")
            case .noParticipantProfile:
                return appString("They haven't accepted the invitation yet.")
            case .grantMissing:
                return appString("This share isn't set up yet.")
            case .verifyFailed:
                return appString("The request couldn't be verified.")
            }
        }
    }

    private lazy var container = CKContainer(identifier: ApprovalConfig.containerID)
    private var database: CKDatabase { container.privateCloudDatabase }

    /// Device-local registry of approval zones this owner created (zone names
    /// are opaque; recipient labels live only here, never in CloudKit).
    private static let zonesKey = "approval_owner_zone_names"

    static var ownedZoneNames: [String] {
        UserDefaults.standard.stringArray(forKey: zonesKey) ?? []
    }

    private static func registerZone(_ name: String) {
        var names = ownedZoneNames
        guard !names.contains(name) else { return }
        names.append(name)
        UserDefaults.standard.set(names, forKey: zonesKey)
    }

    static func unregisterZone(_ name: String) {
        UserDefaults.standard.set(ownedZoneNames.filter { $0 != name }, forKey: zonesKey)
    }

    // MARK: Share creation (durable successor of the Phase-1 spike flow)

    struct ShareSetup {
        let zoneID: CKRecordZone.ID
        let shareURL: URL?
    }

    /// Idempotently create (or reuse) the per-recipient zone, its zone-wide
    /// share restricted to a looked-up participant, and the owner ALERT
    /// subscription. The recipient must accept with the iCloud account that
    /// owns `recipientEmail`.
    func createShare(recipientEmail: String, existingZoneName: String? = nil) async throws -> ShareSetup {
        let email = recipientEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else { throw Failure.invalidRecipientEmail }
        if let blocker = await ApprovalPrerequisites.check() {
            throw Failure.prerequisitesBlocked(blocker)
        }
        let zoneName = existingZoneName ?? ApprovalConfig.opaqueZoneName()
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])

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
        let saved = try await database.modifyRecords(saving: [share], deleting: [])
        for (_, result) in saved.saveResults { _ = try result.get() }
        try await saveOwnerAlertSubscription(zoneID: zoneID)
        Self.registerZone(zoneName)
        let url = (try? await fetchShare(zoneID: zoneID))?.url ?? share.url
        return ShareSetup(zoneID: zoneID, shareURL: url)
    }

    /// User-visible alert when a participant CREATES an ApprovalRequest (ADR-5).
    /// Must stay scoped to that record type — a zone-wide subscription alerts
    /// on every participant write (profile publish, and the idempotent
    /// acceptance-resume re-publishes it), producing phantom "code requested"
    /// notifications before any request exists. Static, localized copy via
    /// the notification localization keys — no item/account/code.
    private func saveOwnerAlertSubscription(zoneID: CKRecordZone.ID) async throws {
        let subscriptionID = ApprovalConfig.requestSubscriptionID(zoneName: zoneID.zoneName)
        // Drop any previously deployed zone-wide subscription under this id
        // first — CloudKit can't morph a subscription's type in place.
        _ = try? await database.modifySubscriptions(saving: [], deleting: [subscriptionID])
        let subscription = CKQuerySubscription(
            recordType: ApprovalConfig.requestRecordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation])
        subscription.zoneID = zoneID
        let info = CKSubscription.NotificationInfo()
        info.titleLocalizationKey = "approval.push.title"
        info.alertLocalizationKey = "approval.push.body"
        info.soundName = "default"
        subscription.notificationInfo = info
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
    }

    private func fetchShare(zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        return try await database.record(for: id) as? CKShare
    }

    // MARK: Participant profile → grant

    func fetchParticipantProfile(zoneID: CKRecordZone.ID)
        async throws -> (participantPubKey: Data, deviceSigningKeys: [Data], createdAtUnixMs: Int64) {
        let id = CKRecord.ID(recordName: ApprovalConfig.participantProfileRecordName, zoneID: zoneID)
        guard let record = try? await database.record(for: id),
              let profile = ApprovalRecordMapping.participantProfile(from: record) else {
            throw Failure.noParticipantProfile
        }
        return profile
    }

    /// Build, sign, and publish the grant plus freshly sealed `shared` blobs
    /// (replacing any prior blobs for the zone — re-share after item edits).
    /// `sharedValues` carries the plaintext of `shared`-capability fields;
    /// the caller guarantees the vault is unlocked.
    func publishGrant(itemId: String,
                      capabilities: [String: FieldCapability],
                      sharedValues: [String: Data],
                      displayTitle: String,
                      displayWebsiteHost: String?,
                      participantPubKey: Data,
                      pinnedDeviceSigningKeys: [Data],
                      epoch: UInt32,
                      zoneID: CKRecordZone.ID,
                      nowUnixMs: Int64) async throws -> AccessGrant {
        let identity = try DeviceSigningIdentity.loadOrCreate()
        var grant = AccessGrant(
            id: ApprovalConfig.opaqueName(), itemId: itemId,
            recipientId: ApprovalConfig.opaqueName(),
            participantPubKey: participantPubKey,
            pinnedDeviceSigningKeys: pinnedDeviceSigningKeys,
            capabilities: capabilities, epoch: epoch,
            createdAtUnixMs: nowUnixMs, expiresAtUnixMs: nil,
            ownerSigningPubKey: identity.publicKeyRaw, ownerSignature: Data())
        grant.ownerSignature = try identity.signature(for: grant.signingBody())

        var records: [CKRecord] = [ApprovalRecordMapping.grantRecord(grant, zoneID: zoneID)]
        // Presentation metadata rides in its OWN encrypted envelope — never
        // inside the signed grant (rename must not re-sign authorization)
        // and never as plaintext CloudKit fields (metadata hygiene).
        let display = SharedDisplayEnvelope(title: displayTitle,
                                            websiteHost: displayWebsiteHost,
                                            updatedAtUnixMs: nowUnixMs, revision: 1)
        records.append(ApprovalRecordMapping.displayEnvelopeRecord(
            sealedBlob: try display.sealed(toParticipantPubKey: participantPubKey,
                                           grantId: grant.id),
            grantId: grant.id, zoneID: zoneID))
        for (fieldId, plaintext) in sharedValues {
            guard capabilities[fieldId]?.isSharedValue == true else { continue }
            let sealed = try ApprovalSeal.sealSharedField(plaintext,
                                                          toParticipantPubKey: participantPubKey,
                                                          grantId: grant.id, fieldId: fieldId)
            records.append(ApprovalRecordMapping.sharedFieldRecord(
                sealedBlob: sealed, grantId: grant.id, fieldId: fieldId, zoneID: zoneID))
        }
        // Old blobs became garbage the moment the grant id rotated; delete them.
        let staleBlobIDs = try await recordIDs(ofType: ApprovalConfig.sharedFieldRecordType, zoneID: zoneID)
        let saved = try await database.modifyRecords(saving: records, deleting: staleBlobIDs,
                                                     savePolicy: .allKeys)
        for (_, result) in saved.saveResults { _ = try result.get() }
        return grant
    }

    // MARK: Inbound requests

    /// Fresh server fetch — the epoch check must never trust a cached grant.
    func fetchGrantFresh(zoneID: CKRecordZone.ID) async throws -> AccessGrant {
        let id = CKRecord.ID(recordName: ApprovalConfig.grantRecordName, zoneID: zoneID)
        guard let record = try? await database.record(for: id),
              let grant = ApprovalRecordMapping.grant(from: record) else {
            throw Failure.grantMissing
        }
        return grant
    }

    /// All request records currently in the zone that are still within their
    /// lifetime. STATELESS full refetch (nil cursor) — this is a state query,
    /// and a persisted cursor would hide every request an earlier scan saw.
    func fetchLiveRequests(zoneID: CKRecordZone.ID, nowUnixMs: Int64) async throws -> [ApprovalRequest] {
        var requests: [ApprovalRequest] = []
        try await ZoneDeltaFetch.pull(database: database, zoneID: zoneID, cursor: nil) { record in
            if let request = ApprovalRecordMapping.request(from: record) {
                requests.append(request)
            }
        }
        return requests.filter { nowUnixMs < $0.expiresAtUnixMs }
    }

    /// Full owner-side verification (kernel) with the authoritative CloudKit
    /// nonce store. Trust root V1: this device's own signing identity signs
    /// all grants (multi-device owner signing is a Phase-3+ open item).
    func verifyInbound(_ request: ApprovalRequest, zoneID: CKRecordZone.ID,
                       nowUnixMs: Int64) async throws -> AccessGrant {
        let grant = try await fetchGrantFresh(zoneID: zoneID)
        let identity = try DeviceSigningIdentity.loadOrCreate()
        let nonceStore = CloudKitNonceStore(zoneName: zoneID.zoneName)
        if let failure = await ApprovalVerifier.verifyRequest(
            request, grant: grant,
            trustedOwnerSigningKeys: [identity.publicKeyRaw],
            currentEpoch: grant.epoch, nowUnixMs: nowUnixMs, nonceStore: nonceStore) {
            throw Failure.verifyFailed(failure)
        }
        return grant
    }

    /// Sign and publish the owner's decision. Idempotent by construction:
    /// deterministic record name + `.allKeys` means a CloudKit retry after an
    /// ambiguous timeout overwrites the identical response instead of failing
    /// "record to insert already exists" (seen in device QA — the first save
    /// had actually landed).
    func respond(requestId: String, decision: ApprovalDecision, sealedPayload: Data?,
                 zoneID: CKRecordZone.ID, nowUnixMs: Int64) async throws {
        let identity = try DeviceSigningIdentity.loadOrCreate()
        var response = ApprovalResponse(requestId: requestId, decision: decision,
                                        sealedPayload: sealedPayload,
                                        respondedAtUnixMs: nowUnixMs,
                                        ownerSigningPubKey: identity.publicKeyRaw,
                                        ownerSignature: Data())
        response.ownerSignature = try identity.signature(for: response.signingBody())
        let record = ApprovalRecordMapping.responseRecord(response, zoneID: zoneID)
        let saved = try await database.modifyRecords(saving: [record], deleting: [],
                                                     savePolicy: .allKeys)
        for (_, result) in saved.saveResults { _ = try result.get() }
        // An answered request is spent: remove its record so inbox refreshes
        // stop resurfacing it (its nonce is burned — a re-approve can only
        // fail verification). Separate best-effort call, NOT part of the
        // response batch: a retried delete of an already-gone record must
        // not fail the idempotent response save, and the record's TTL plus
        // the coordinator's handled-set cover a missed delete.
        _ = try? await database.modifyRecords(
            saving: [], deleting: [CKRecord.ID(recordName: requestId, zoneID: zoneID)])
    }

    // MARK: Revocation (owner)

    /// Authoritative revoke: deleting the zone removes the CKShare (B loses
    /// the zone immediately), every grant/blob/request/response/nonce in it,
    /// and the alert subscription. Verify-time enforcement already exists —
    /// the approve path fetches the grant FRESH, so a deleted zone fails with
    /// `zoneNotFound` before any code could be issued. Already-delivered
    /// `shared` values remain with B (stated in the revoke confirm — H5).
    func revoke(zoneName: String, inviteRecordName: String? = nil) async throws {
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        _ = try await database.modifyRecordZones(saving: [], deleting: [zoneID])
        // A dangling public invite record would keep resolving to a dead zone
        // for up to 7 days — delete it with the share it belonged to.
        if let inviteRecordName {
            _ = try? await container.publicCloudDatabase.modifyRecords(
                saving: [], deleting: [CKRecord.ID(recordName: inviteRecordName)])
        }
        _ = try? await database.modifySubscriptions(
            saving: [], deleting: [ApprovalConfig.requestSubscriptionID(zoneName: zoneName)])
        Self.unregisterZone(zoneName)
    }

    /// Vault-erase cleanup: best-effort revoke of every share this owner
    /// created (the printed registry is device-local; the zones must not
    /// outlive the vault that sealed their content).
    func revokeAllOwned() async {
        for zoneName in Self.ownedZoneNames {
            try? await revoke(zoneName: zoneName)
        }
    }

    private func recordIDs(ofType type: String, zoneID: CKRecordZone.ID) async throws -> [CKRecord.ID] {
        var ids: [CKRecord.ID] = []
        // Stateless: GC must see the CURRENT record set every time.
        try await ZoneDeltaFetch.pull(database: database, zoneID: zoneID, cursor: nil) { record in
            if record.recordType == type { ids.append(record.recordID) }
        }
        return ids
    }
}

/// Authoritative nonce consumption (H4): a nonce is spent by CREATING a
/// marker record named after it. CloudKit's atomic "record already exists"
/// failure makes a second consumption — even from another owner device —
/// collide server-side. The verifier maps a throw to fail-closed rejection.
nonisolated struct CloudKitNonceStore: ApprovalNonceStore {
    /// Stored as the plain zone name so the store stays Sendable.
    let zoneName: String

    func consume(nonce: Data, expiresAtUnixMs: Int64) async throws -> Bool {
        let database = CKContainer(identifier: ApprovalConfig.containerID).privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        let record = ApprovalRecordMapping.nonceRecord(nonce: nonce,
                                                       expiresAtUnixMs: expiresAtUnixMs,
                                                       zoneID: zoneID)
        do {
            let saved = try await database.modifyRecords(saving: [record], deleting: [],
                                                         savePolicy: .ifServerRecordUnchanged)
            for (_, result) in saved.saveResults {
                if case .failure(let error) = result {
                    if Self.isReplayCollision(error) { return false }
                    throw error
                }
            }
            return true
        } catch let error where Self.isReplayCollision(error) {
            return false
        }
    }

    /// "Record already exists" can surface directly, per-record, or wrapped
    /// in `partialFailure` — every shape means the nonce was already spent.
    private static func isReplayCollision(_ error: any Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .serverRecordChanged { return true }
        if ckError.code == .partialFailure,
           let partials = ckError.partialErrorsByItemID?.values {
            return partials.contains { ($0 as? CKError)?.code == .serverRecordChanged }
        }
        return false
    }
}
