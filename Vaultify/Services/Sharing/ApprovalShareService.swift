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
        /// Single-device requested but the recipient never published a
        /// per-device key directory (pre-P03a app) — sealing to the legacy
        /// synced key would silently void the single-device promise (INV-04).
        case recipientNeedsUpdate

        var errorDescription: String? {
            switch self {
            case .invalidRecipientEmail:
                return appString("Enter the recipient's iCloud email first.")
            case .prerequisitesBlocked:
                return appString("Sharing isn't available right now. Check iCloud and notification permissions.")
            case .noParticipantProfile:
                return appString("They haven't accepted the invitation yet.")
            case .grantMissing:
                return appString("This share isn't set up yet.")
            case .verifyFailed:
                return appString("The request couldn't be verified.")
            case .recipientNeedsUpdate:
                return appString("Single-device sharing needs the recipient to update Loox first.")
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
        try await saveAcceptanceSubscription(zoneID: zoneID)
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

    /// SILENT push when the participant CREATES their identity profile — the
    /// event that turns "waiting" into "ready for the fingerprint ceremony"
    /// on the owner side. Must stay content-available only: an alert-style
    /// subscription on profile writes produced phantom notifications (the
    /// acceptance resume re-publishes the profile idempotently), which is why
    /// the user-visible subscription above is scoped to ApprovalRequest. A
    /// redundant silent hint just triggers a cheap, single-flighted refresh.
    /// Internal (not private) so a launch-time pass can backfill it onto
    /// shares created before this subscription existed.
    func saveAcceptanceSubscription(zoneID: CKRecordZone.ID) async throws {
        let subscription = CKQuerySubscription(
            recordType: ApprovalConfig.participantProfileRecordType,
            predicate: NSPredicate(value: true),
            subscriptionID: ApprovalConfig.acceptSubscriptionID(zoneName: zoneID.zoneName),
            options: [.firesOnRecordCreation])
        subscription.zoneID = zoneID
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true // silent — no banner, no sound
        subscription.notificationInfo = info
        // Saving under the same id is an upsert, so the idempotent
        // createShare resume/nudge path never trips over an existing one.
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
    }

    private func fetchShare(zoneID: CKRecordZone.ID) async throws -> CKShare? {
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        return try await database.record(for: id) as? CKShare
    }

    /// Whether the invited recipient has accepted the CKShare — the
    /// authoritative CloudKit-level signal, set the moment they accept and
    /// independent of whether their device has published its profile yet. Lets
    /// the owner distinguish "not accepted" from "accepted, device still
    /// finishing" without waiting on the profile poll. Best-effort: a fetch
    /// miss (offline/not-yet-propagated) reads as not-accepted.
    func participantAccepted(zoneID: CKRecordZone.ID) async -> Bool {
        guard let share = try? await fetchShare(zoneID: zoneID) else {
            ShareDiagnostics.log("OWNER", "participantAccepted: no share for \(zoneID.zoneName)")
            return false
        }
        let statuses = share.participants.map { "\($0.role.rawValue):\($0.acceptanceStatus.rawValue)" }
        let accepted = share.participants.contains {
            $0.role != .owner && $0.acceptanceStatus == .accepted
        }
        ShareDiagnostics.log("OWNER", "participantAccepted=\(accepted) zone=\(zoneID.zoneName) "
            + "participants=[\(statuses.joined(separator: ","))]")
        return accepted
    }

    // MARK: Participant profile → grant

    func fetchParticipantProfile(zoneID: CKRecordZone.ID)
        async throws -> (participantPubKey: Data, deviceSigningKeys: [Data],
                         deviceHPKEDirectory: [DeviceHPKEDirectoryEntry], createdAtUnixMs: Int64) {
        let id = CKRecord.ID(recordName: ApprovalConfig.participantProfileRecordName, zoneID: zoneID)
        guard let record = try? await database.record(for: id),
              let profile = ApprovalRecordMapping.participantProfile(from: record) else {
            ShareDiagnostics.log("OWNER", "fetchParticipantProfile: NONE in \(zoneID.zoneName)")
            throw Failure.noParticipantProfile
        }
        ShareDiagnostics.log("OWNER", "fetchParticipantProfile: FOUND in \(zoneID.zoneName)")
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
                      displayFields: [String: SharedDisplayEnvelope.FieldMeta],
                      participantPubKey: Data,
                      pinnedDeviceSigningKeys: [Data],
                      epoch: UInt32,
                      zoneID: CKRecordZone.ID,
                      nowUnixMs: Int64,
                      deviceScope: DeviceScope = .multi,
                      allowedDevices: [DeviceHPKEDirectoryEntry] = [],
                      displayPasskeys: [SharedDisplayEnvelope.PasskeyMeta] = []) async throws -> AccessGrant {
        let identity = try DeviceSigningIdentity.loadOrCreate()
        // Single-device is meaningless without at least one enrolled device
        // key — and it must NEVER fall back to the legacy synced participant
        // key (INV-04): fail loudly instead.
        if deviceScope == .single {
            guard !allowedDevices.isEmpty else { throw Failure.recipientNeedsUpdate }
        }
        let bindings = allowedDevices.map {
            DeviceKeyBinding(deviceKeyID: $0.deviceKeyID,
                             hpkePublicKeyHash: Data(SHA256.hash(data: $0.hpkePublicKey)))
        }
        var grant = AccessGrant(
            id: ApprovalConfig.opaqueName(), itemId: itemId,
            recipientId: ApprovalConfig.opaqueName(),
            participantPubKey: participantPubKey,
            pinnedDeviceSigningKeys: pinnedDeviceSigningKeys,
            capabilities: capabilities, epoch: epoch,
            createdAtUnixMs: nowUnixMs, expiresAtUnixMs: nil,
            ownerSigningPubKey: identity.publicKeyRaw, ownerSignature: Data(),
            deviceScope: deviceScope,
            allowedDeviceKeyBindings: deviceScope == .single ? bindings : [])
        grant.ownerSignature = try identity.signature(for: grant.signingBody())

        var records: [CKRecord] = [ApprovalRecordMapping.grantRecord(grant, zoneID: zoneID)]
        // Presentation metadata rides in its OWN encrypted envelope — never
        // inside the signed grant (rename must not re-sign authorization)
        // and never as plaintext CloudKit fields (metadata hygiene).
        var display = SharedDisplayEnvelope(title: displayTitle,
                                            websiteHost: displayWebsiteHost,
                                            updatedAtUnixMs: nowUnixMs, revision: 1,
                                            fields: displayFields)
        display.passkeys = displayPasskeys.isEmpty ? nil : displayPasskeys
        if grant.allowedDeviceKeyBindings.isEmpty {
            records.append(ApprovalRecordMapping.displayEnvelopeRecord(
                sealedBlob: try display.sealed(toParticipantPubKey: participantPubKey,
                                               grantId: grant.id),
                grantId: grant.id, zoneID: zoneID))
        } else {
            var envelopes: [String: Data] = [:]
            for device in allowedDevices {
                envelopes[device.deviceKeyID.hexString] = try display.sealedForDevice(
                    toDevicePubKey: device.hpkePublicKey,
                    deviceKeyID: device.deviceKeyID, grantId: grant.id)
            }
            records.append(ApprovalRecordMapping.displayEnvelopeRecord(
                sealedBlob: try PerDeviceSealedBlob(envelopes: envelopes).encoded(),
                grantId: grant.id, zoneID: zoneID))
        }
        for (fieldId, plaintext) in sharedValues {
            guard capabilities[fieldId]?.isSharedValue == true else { continue }
            let sealed: Data
            if grant.allowedDeviceKeyBindings.isEmpty {
                sealed = try ApprovalSeal.sealSharedField(plaintext,
                                                          toParticipantPubKey: participantPubKey,
                                                          grantId: grant.id, fieldId: fieldId)
            } else {
                var envelopes: [String: Data] = [:]
                for device in allowedDevices {
                    envelopes[device.deviceKeyID.hexString] = try ApprovalSeal.sealSharedFieldForDevice(
                        plaintext, toDevicePubKey: device.hpkePublicKey,
                        deviceKeyID: device.deviceKeyID,
                        grantId: grant.id, fieldId: fieldId)
                }
                sealed = try PerDeviceSealedBlob(envelopes: envelopes).encoded()
            }
            records.append(ApprovalRecordMapping.sharedFieldRecord(
                sealedBlob: sealed, grantId: grant.id, fieldId: fieldId, zoneID: zoneID))
        }
        // Flag OFF (default, legacy): a zone holds at most ONE grant, so
        // clean-replacing EVERY `ApprovalSharedField` blob in the zone is
        // exactly the pre-Family-sharing behavior, byte for byte — and it
        // is REQUIRED for back-compat here: `grant.id` is freshly minted
        // above, so scoping the delete to it would match zero records (the
        // id has never existed before) and silently orphan the PRIOR
        // grant's field ciphertext on every re-share/edit instead of
        // replacing it, which is what shipped before this transport existed.
        // Flag ON (Family sharing): scope to THIS grant's id only, so a
        // sibling grant's fields in the same zone are never wiped
        // (INV-FAM-01).
        let staleBlobIDs = try await sharedFieldRecordIDs(
            grantId: FamilyShareTransport.perGrantEnabled ? grant.id : nil, zoneID: zoneID)
        // Flag ON only (Project A, phase A3): a re-share of the SAME item
        // must REPLACE its prior grant, never duplicate it. `grant.id` above
        // is freshly minted, so `staleBlobIDs` just above (scoped to it) can
        // never match a PRIOR grant for this item — find that prior grant
        // (if any) by the AUTHENTICATED decoded `itemId`, never a record
        // name (INV-FAM-01), and fold its full footprint (grant + display +
        // fields) into the same delete batch so create/replace is one write.
        let supersededIDs = FamilyShareTransport.perGrantEnabled
            ? try await supersededGrantRecordIDs(itemId: itemId, zoneID: zoneID)
            : []
        let saved = try await database.modifyRecords(saving: records,
                                                     deleting: staleBlobIDs + supersededIDs,
                                                     savePolicy: .allKeys)
        for (_, result) in saved.saveResults { _ = try result.get() }
        return grant
    }

    /// Owner renamed the item (or its website changed): reseal ONLY the
    /// display envelope with a bumped revision — presentation metadata has
    /// its own lifecycle, the signed grant is untouched (U2). Revision is
    /// second-granular monotonic so recipients drop out-of-order updates.
    func republishDisplayEnvelope(title: String, websiteHost: String?,
                                  displayFields: [String: SharedDisplayEnvelope.FieldMeta],
                                  zoneID: CKRecordZone.ID, nowUnixMs: Int64) async throws {
        let grant = try await fetchGrantFresh(zoneID: zoneID)
        let display = SharedDisplayEnvelope(title: title, websiteHost: websiteHost,
                                            updatedAtUnixMs: nowUnixMs,
                                            revision: UInt32(clamping: nowUnixMs / 1000),
                                            fields: displayFields)
        let record = ApprovalRecordMapping.displayEnvelopeRecord(
            sealedBlob: try display.sealed(toParticipantPubKey: grant.participantPubKey,
                                           grantId: grant.id),
            grantId: grant.id, zoneID: zoneID)
        let saved = try await database.modifyRecords(saving: [record], deleting: [],
                                                     savePolicy: .allKeys)
        for (_, result) in saved.saveResults { _ = try result.get() }
    }

    /// Owner edited the item: re-seal the CURRENT values of every `shared`
    /// field so the recipient's projection follows edits near-realtime (the
    /// shared-db silent push triggers their refresh). Authorization is
    /// untouched — same grant, same capabilities, fresh ciphertext.
    func republishSharedValues(values: [String: Data],
                               zoneID: CKRecordZone.ID) async throws {
        let grant = try await fetchGrantFresh(zoneID: zoneID)
        var records: [CKRecord] = []
        for (fieldId, plaintext) in values
        where grant.capabilities[fieldId]?.isSharedValue == true {
            let sealed = try ApprovalSeal.sealSharedField(
                plaintext, toParticipantPubKey: grant.participantPubKey,
                grantId: grant.id, fieldId: fieldId)
            records.append(ApprovalRecordMapping.sharedFieldRecord(
                sealedBlob: sealed, grantId: grant.id, fieldId: fieldId, zoneID: zoneID))
        }
        guard !records.isEmpty else { return }
        // Old blobs are superseded ciphertext for THIS grant — replace
        // atomically, scoped to `grant.id` so a sibling grant's fields in
        // the same zone are never touched (INV-FAM-01), same pattern as
        // publishGrant's stale cleanup.
        let staleBlobIDs = try await sharedFieldRecordIDs(grantId: grant.id, zoneID: zoneID)
        let saved = try await database.modifyRecords(saving: records, deleting: staleBlobIDs,
                                                     savePolicy: .allKeys)
        for (_, result) in saved.saveResults { _ = try result.get() }
    }

    // MARK: Inbound requests

    /// Fresh server fetch — the epoch check must never trust a cached grant.
    /// Reads the LEGACY singleton only: owner-side republish/verify against a
    /// SPECIFIC grant in a multi-grant zone needs `SharingStore`'s
    /// per-(zone,item) → grantId identity (Project A, phase A2) to know which
    /// grant it means. Inert while `FamilyShareTransport.perGrantEnabled` is
    /// off (default) — the owner never publishes anything else to fetch here.
    func fetchGrantFresh(zoneID: CKRecordZone.ID) async throws -> AccessGrant {
        let id = CKRecord.ID(recordName: ApprovalConfig.legacyGrantRecordName, zoneID: zoneID)
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
            saving: [],
            deleting: [ApprovalConfig.requestSubscriptionID(zoneName: zoneName),
                       ApprovalConfig.acceptSubscriptionID(zoneName: zoneName)])
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

    /// Record IDs of every `ApprovalSharedField` in the zone — scoped to
    /// `grantId` when given (matched by the AUTHENTICATED cleartext
    /// `grantId` field each record already carries, via
    /// `ApprovalRecordMapping.sharedFieldRecord` — never by name or
    /// name-prefix, INV-FAM-01), or EVERY field record in the zone when
    /// `grantId` is nil. The nil case exists solely for the legacy
    /// (`FamilyShareTransport.perGrantEnabled == false`) clean-replacement
    /// in `publishGrant` — matches by `recordType` only, same as pre-A1,
    /// since a legacy zone holds at most one grant and "all" and "this
    /// grant's" are the same set there.
    private func sharedFieldRecordIDs(grantId: String?, zoneID: CKRecordZone.ID) async throws -> [CKRecord.ID] {
        var ids: [CKRecord.ID] = []
        // Stateless: cleanup must see the CURRENT record set every time.
        try await ZoneDeltaFetch.pull(database: database, zoneID: zoneID, cursor: nil) { record in
            guard record.recordType == ApprovalConfig.sharedFieldRecordType else { return }
            if let grantId {
                guard let field = ApprovalRecordMapping.sharedField(from: record),
                      field.grantId == grantId else { return }
            }
            ids.append(record.recordID)
        }
        return ids
    }

    // MARK: Family Space-share support (Project A, phase A3)
    //
    // Owner-side "every live grant in a zone" read + a per-grant (not
    // per-zone) revoke — both used by `SpaceShareMembershipExecutor` to
    // execute a `SpaceShareMembershipReconciler.Ops` plan. Neither runs in
    // production yet: the executor isn't wired to any UI, and
    // `FamilyShareTransport.perGrantEnabled` stays off this stage.

    /// Every LIVE, OWNER-SIGNED `ApprovalGrant` currently published into this
    /// zone — the owner's OWN private-DB copy (NOT the recipient's shared-DB
    /// projection `ApprovalRecipientService.fetchAllGrants` reads; a zone the
    /// owner created never appears in their OWN `sharedCloudDatabase`).
    /// Reuses `ApprovalRecipientService.dedupedLiveGrants` verbatim (no new
    /// verify/dedupe logic here): a recipient holds `.readWrite` on a shared
    /// zone (`createShare`), so a compromised recipient device could
    /// otherwise inject a same-shaped `ApprovalGrant` record that would make
    /// the Space-share reconciler believe an item is already synced when it
    /// is not — fail-safe (under-share, never a leak), the exact same threat
    /// `dedupedLiveGrants` already defends against (verify-before-dedupe, so
    /// a same-id forgery can never evict the legitimate grant).
    func fetchAllGrants(zoneID: CKRecordZone.ID, nowUnixMs: Int64) async throws -> [AccessGrant] {
        let identity = try DeviceSigningIdentity.loadOrCreate()
        let records = try await allZoneRecords(zoneID: zoneID)
        return ApprovalRecipientService.dedupedLiveGrants(
            from: records, pinnedOwnerSigningKey: identity.publicKeyRaw, nowUnixMs: nowUnixMs)
    }

    /// Delete ONE grant — its grant record, its display record, and every
    /// field record scoped to it — never the zone, never a sibling grant
    /// (INV-FAM-01). Used by the Space-share reconciler's per-item revoke
    /// (an item left the Space, was deleted, or became ineligible);
    /// `revoke(zoneName:)` above remains the separate whole-member/zone-level
    /// revoke and is untouched by this.
    func revokeGrant(_ grantId: String, zoneID: CKRecordZone.ID) async throws {
        let records = try await allZoneRecords(zoneID: zoneID)
        let ids = Self.recordIDs(forGrantId: grantId, in: records)
        guard !ids.isEmpty else { return }
        _ = try await database.modifyRecords(saving: [], deleting: ids)
    }

    /// Every record currently in the zone (owner's private DB) — the shared
    /// scan behind `fetchAllGrants`, `revokeGrant`, and
    /// `supersededGrantRecordIDs`. Stateless (nil cursor): every caller needs
    /// the CURRENT record set, same rationale as `sharedFieldRecordIDs`.
    private func allZoneRecords(zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        try await ZoneDeltaFetch.pull(database: database, zoneID: zoneID, cursor: nil) {
            records.append($0)
        }
        return records
    }

    /// IO wrapper around the pure `supersededRecordIDs(forItemId:in:)` below,
    /// used by `publishGrant`'s flag-on replace-on-republish path.
    private func supersededGrantRecordIDs(itemId: String, zoneID: CKRecordZone.ID) async throws -> [CKRecord.ID] {
        let records = try await allZoneRecords(zoneID: zoneID)
        return Self.supersededRecordIDs(forItemId: itemId, in: records)
    }

    /// Pure + unit-tested: any PRIOR grant(s) for `itemId` found in `records`
    /// — matched by the AUTHENTICATED decoded `itemId`, never a record name
    /// (INV-FAM-01) — reduced to the full record-id footprint (grant +
    /// display + fields) `publishGrant` must delete so a re-share of the
    /// same item REPLACES rather than duplicates it. Empty when no prior
    /// grant for this item exists. (Normally at most one match; a defensive
    /// loop in case a bug ever left more than one — deduped, so a grant
    /// found under two names, e.g. a legacy singleton alongside a per-grant
    /// record describing the same id, never yields the same record id twice
    /// in one CloudKit delete batch.)
    nonisolated static func supersededRecordIDs(forItemId itemId: String, in records: [CKRecord]) -> [CKRecord.ID] {
        var ids: [CKRecord.ID] = []
        var seen: Set<CKRecord.ID> = []
        for record in records {
            guard let grant = ApprovalRecordMapping.grant(from: record), grant.itemId == itemId else { continue }
            for id in recordFootprint(forGrant: grant, record: record, allRecords: records)
            where !seen.contains(id) {
                seen.insert(id)
                ids.append(id)
            }
        }
        return ids
    }

    /// Pure + unit-tested: one grant's full record-id footprint, found by its
    /// OWN id (the executor's per-item revoke). Empty when `grantId` isn't
    /// found among `records`.
    nonisolated static func recordIDs(forGrantId grantId: String, in records: [CKRecord]) -> [CKRecord.ID] {
        for record in records {
            guard let grant = ApprovalRecordMapping.grant(from: record), grant.id == grantId else { continue }
            return recordFootprint(forGrant: grant, record: record, allRecords: records)
        }
        return []
    }

    /// One grant's grant record, its display record, and every field record
    /// scoped to its id. `record` is the ALREADY-MATCHED grant record from a
    /// zone scan; `allRecords` is that SAME scan, reused for the field lookup
    /// so callers pay for one scan, not N+1. If `record` was found under the
    /// legacy singleton name, the legacy display name is included too — the
    /// legacy grant + display are always written TOGETHER (both keyed off
    /// the SAME `FamilyShareTransport.perGrantEnabled` value at write time),
    /// so a legacy-named grant's display is never at the deterministic
    /// per-grant name.
    private nonisolated static func recordFootprint(forGrant grant: AccessGrant, record: CKRecord,
                                                     allRecords: [CKRecord]) -> [CKRecord.ID] {
        var ids: [CKRecord.ID] = [record.recordID]
        let zoneID = record.recordID.zoneID
        ids.append(CKRecord.ID(recordName: ApprovalConfig.displayEnvelopeRecordName(grantId: grant.id),
                               zoneID: zoneID))
        if record.recordID.recordName == ApprovalConfig.legacyGrantRecordName {
            ids.append(CKRecord.ID(recordName: ApprovalConfig.legacyDisplayEnvelopeRecordName, zoneID: zoneID))
        }
        for candidate in allRecords {
            guard let field = ApprovalRecordMapping.sharedField(from: candidate),
                  field.grantId == grant.id else { continue }
            ids.append(candidate.recordID)
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
