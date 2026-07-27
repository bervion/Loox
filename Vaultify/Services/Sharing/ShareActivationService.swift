import CloudKit
import Foundation

/// Finishes an outgoing share once the recipient's identity profile lands.
///
/// The owner authorizes a share ONCE, when they tap Create: that is where they
/// name the recipient and choose the field scope. Sealing has to wait for the
/// recipient's public key (`ApprovalCrypto` seals to it, and the signed grant
/// body binds key + capabilities together), but waiting is the CRYPTO's
/// constraint, not the owner's decision — so the selection is frozen onto the
/// share record at create time and replayed here.
///
/// Both entry points run through this one implementation:
/// - the share sheet, while the owner is still watching the waiting screen
/// - `OwnerShareRefresher`, when the profile lands after the sheet was dismissed
///   (which is the normal case — the waiting copy tells the owner to leave)
///
/// so the in-sheet and off-sheet completions can never drift apart.
///
/// Requires an unlocked vault: sealing passkey material reads the live Vault
/// Key, and the composer fails loudly rather than publishing a grant that names
/// a passkey with nothing behind it. When locked this reports `.needsUnlock` and
/// the caller leaves the record ready, to be retried on the next unlock.
@MainActor final class ShareActivationService {
    /// Shape returned by `ApprovalShareService.fetchParticipantProfile` (an
    /// anonymous tuple there); named here so the two entry points below can
    /// share one signature.
    typealias ParticipantProfile = (participantPubKey: Data, deviceSigningKeys: [Data],
                                    deviceHPKEDirectory: [DeviceHPKEDirectoryEntry],
                                    createdAtUnixMs: Int64)

    enum Outcome: Equatable {
        /// Grant published; the record is now active.
        case activated
        /// Recipient has not published their profile yet — nothing to do.
        case notReady
        /// Vault is locked, or the item is gone. Retry after the next unlock.
        case needsUnlock
        /// The owner never recorded a scope for this share (a record written
        /// before scope was persisted). Only a human can supply it, so the
        /// caller must route to the config form.
        case needsOwnerScope
        case failed(String)
    }

    private let sharingStore: SharingStore
    private let shareService: ApprovalShareService
    private let repository: VaultRepository
    private let session: VaultSession
    private let store: VaultStore
    private let inviteLinks: InviteLinkService

    init(sharingStore: SharingStore, shareService: ApprovalShareService,
         repository: VaultRepository, session: VaultSession, store: VaultStore,
         inviteLinks: InviteLinkService) {
        self.sharingStore = sharingStore
        self.shareService = shareService
        self.repository = repository
        self.session = session
        self.store = store
        self.inviteLinks = inviteLinks
    }

    /// Publish the grant for a share whose recipient has published a profile.
    /// Idempotent: an already-confirmed record returns `.activated` untouched.
    @discardableResult
    func activate(record: ItemShareRecord) async -> Outcome {
        guard !record.fingerprintConfirmed else { return .activated }
        guard let capabilities = record.plannedCapabilities else { return .needsOwnerScope }
        guard let item = repository.item(id: record.itemId) else { return .needsUnlock }

        let zoneID = CKRecordZone.ID(zoneName: record.zoneName)
        guard let profile = try? await shareService.fetchParticipantProfile(zoneID: zoneID) else {
            return .notReady
        }
        return await publish(record: record, item: item, capabilities: capabilities,
                             zoneID: zoneID, profile: profile)
    }

    /// Same publish, for a caller that already holds the fetched profile (the
    /// sheet's poll) — avoids a redundant round trip.
    @discardableResult
    func activate(record: ItemShareRecord,
                  profile: ParticipantProfile) async -> Outcome {
        guard !record.fingerprintConfirmed else { return .activated }
        guard let capabilities = record.plannedCapabilities else { return .needsOwnerScope }
        guard let item = repository.item(id: record.itemId) else { return .needsUnlock }
        return await publish(record: record, item: item, capabilities: capabilities,
                             zoneID: CKRecordZone.ID(zoneName: record.zoneName), profile: profile)
    }

    private func publish(record: ItemShareRecord, item: VaultItem,
                         capabilities: [String: FieldCapability],
                         zoneID: CKRecordZone.ID,
                         profile: ParticipantProfile) async -> Outcome {
        // Passkey sealing needs the live key. Bail before touching CloudKit so a
        // locked vault leaves the record exactly as it was, ready to retry.
        guard session.vaultKey != nil else { return .needsUnlock }

        let itemPasskeys = repository.passkeys.filter { item.matchesRelyingParty($0.relyingParty) }
        // Absent flag means a record written before scope was persisted; those
        // never reach here (guarded above), so the fallback is only for the
        // Space fan-out's own records, which are multi-device by construction.
        let deviceScope: DeviceScope = (record.plannedAllowMultipleDevices ?? true) ? .multi : .single
        let nowUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
        do {
            let grant = try await SharedGrantComposer.publish(
                service: shareService, store: store, item: item,
                capabilities: capabilities, itemPasskeys: itemPasskeys,
                vaultKey: session.vaultKey,
                profile: SharedGrantComposer.RecipientProfile(
                    participantPubKey: profile.participantPubKey,
                    deviceSigningKeys: profile.deviceSigningKeys,
                    deviceHPKEDirectory: profile.deviceHPKEDirectory),
                deviceScope: deviceScope, epoch: 1, zoneID: zoneID, nowUnixMs: nowUnixMs)
            await garbageCollectInviteArtifacts(record)
            var activated = record
            activated.grantId = grant.id
            activated.fingerprintConfirmed = true
            activated.createdAtUnixMs = nowUnixMs
            sharingStore.upsert(activated)
            ShareDiagnostics.log("OWNER", "activated \(record.zoneName) grant=\(grant.id)")
            return .activated
        } catch {
            ShareDiagnostics.log("OWNER", "activation failed \(record.zoneName): \(error)")
            return .failed(error.localizedDescription)
        }
    }

    /// Acceptance is proven, so the public-DB invite and rendezvous records have
    /// served their purpose. Best-effort and creator-only; the names stay on the
    /// record so revoke can retry the same GC.
    private func garbageCollectInviteArtifacts(_ record: ItemShareRecord) async {
        if let inviteRecordName = record.inviteRecordName {
            await inviteLinks.deleteInvite(recordName: inviteRecordName)
        }
        if let dropRecordName = record.dropRecordName {
            await inviteLinks.deleteInvite(recordName: dropRecordName)
        }
    }
}
