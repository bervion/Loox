import CloudKit
import Foundation

/// Recipient-side shared items as first-class `VaultItem`s (V1.2 plan, V1/V2).
///
/// A PROJECTION, not storage: models are rebuilt from the accepted shared
/// zones (grant + display envelope + sealed shared values) and live only in
/// memory. They deliberately never touch `VaultStore` — vault-item sync,
/// backup, export, Watchtower, and AutoFill all read the store and must see
/// zero shared items. Revoke = the zone disappears = the item disappears.
@MainActor @Observable final class SharedItemsProjection {
    /// Projected items, title-sorted. Each carries `sharedOrigin`.
    private(set) var items: [VaultItem] = []

    /// Request state machines keyed by "grantId|fieldId" — an in-flight
    /// WAITING machine holds the ephemeral HPKE key and MUST survive
    /// push-driven refreshes of the SAME grant; a re-granted share (new
    /// grant id) gets fresh models.
    @ObservationIgnored private var requestModels: [String: RequestCodeModel] = [:]
    /// Per-item origin + decoded grant (capability lookups in the detail UI).
    @ObservationIgnored private var grants: [String: AccessGrant] = [:]
    @ObservationIgnored private let recipient: ApprovalRecipientService
    @ObservationIgnored private let escrow: ParticipantEscrowService
    private var refreshing = false

    init(recipient: ApprovalRecipientService, escrow: ParticipantEscrowService) {
        self.recipient = recipient
        self.escrow = escrow
    }

    // MARK: Lookups (detail screen + lists)

    func item(id: String) -> VaultItem? { items.first { $0.id == id } }

    func grant(forItem id: String) -> AccessGrant? { grants[id] }

    /// Lazy per-field request machine (askEachTime TOTP capabilities).
    func requestModel(forItem id: String, fieldId: String) -> RequestCodeModel? {
        guard let origin = item(id: id)?.sharedOrigin, let grant = grants[id],
              grant.capabilities[fieldId]?.isAskEachTimeTOTP == true else { return nil }
        let key = "\(grant.id)|\(fieldId)"
        if let existing = requestModels[key] { return existing }
        let model = RequestCodeModel(service: recipient, grant: grant, fieldId: fieldId,
                                     zoneID: Self.zoneID(for: origin))
        requestModels[key] = model
        return model
    }

    /// Safety code for the optional out-of-band comparison row.
    func safetyCode(forItem id: String, vaultKey: [UInt8]) async -> String? {
        guard let grant = grants[id],
              let identity = try? await escrow.ensureIdentity(vaultKey: vaultKey) else { return nil }
        return TrustFingerprint.code(ownerSigningPubKey: grant.ownerSigningPubKey,
                                     participantPubKey: identity.publicKeyRaw)
    }

    func leave(itemId: String, vaultKey: [UInt8]) async throws {
        guard let origin = item(id: itemId)?.sharedOrigin else { return }
        try await recipient.leave(zoneID: Self.zoneID(for: origin))
        await refresh(vaultKey: vaultKey)
    }

    func wipe() {
        items = []
        grants = [:]
        requestModels = [:]
    }

    // MARK: Refresh (single-flight; triggers live on the unlocked shell)

    func refresh(vaultKey: [UInt8]) async {
        guard CloudSyncService.isConfigured, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        guard let identity = try? await escrow.ensureIdentity(vaultKey: vaultKey) else { return }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard let zones = try? await recipient.acceptedApprovalZones() else {
            return // Offline — keep whatever we already show.
        }
        var built: [VaultItem] = []
        var builtGrants: [String: AccessGrant] = [:]
        var liveGrantIDs: Set<String> = []
        for zoneID in zones {
            do {
                let grant = try await recipient.fetchGrant(zoneID: zoneID, nowUnixMs: nowMs)
                // Auto-TOFU pin on first sight (single-confirm pairing model);
                // a later key CHANGE is rejected by the pin store, not re-pinned.
                if ApprovalRecipientService.pinnedOwnerKey(zoneID: zoneID) == nil {
                    try ApprovalRecipientService.pinOwnerKey(grant.ownerSigningPubKey, zoneID: zoneID)
                }
                let values = try await recipient.fetchSharedFieldValues(
                    grant: grant, identity: identity, zoneID: zoneID)
                let display = await recipient.fetchDisplayEnvelope(
                    grant: grant, identity: identity, zoneID: zoneID)
                let origin = SharedOrigin(zoneName: zoneID.zoneName,
                                          ownerName: zoneID.ownerName, grantId: grant.id)
                let item = Self.buildItem(origin: origin, grant: grant,
                                          display: display, values: values)
                built.append(item)
                builtGrants[item.id] = grant
                liveGrantIDs.insert(grant.id)
            } catch let error as CKError
                where error.code == .zoneNotFound || error.code == .userDeletedZone {
                continue // Revoked/left — the item simply stops existing.
            } catch {
                // Transient (offline, throttle): keep the previous projection
                // of THIS zone so the list doesn't flicker empty.
                if let existing = items.first(where: {
                    $0.sharedOrigin?.zoneName == zoneID.zoneName
                        && $0.sharedOrigin?.ownerName == zoneID.ownerName
                }) {
                    built.append(existing)
                    if let grant = grants[existing.id] {
                        builtGrants[existing.id] = grant
                        liveGrantIDs.insert(grant.id)
                    }
                }
            }
        }
        items = built.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        grants = builtGrants
        // Drop machines whose grant rotated or vanished (fresh models next time).
        requestModels = requestModels.filter { key, _ in
            liveGrantIDs.contains(String(key.split(separator: "|")[0]))
        }
    }

    // MARK: Building

    /// Pure mapping (unit-tested): grant + envelope + values → VaultItem.
    /// Shared values render as protected fields (reveal/copy UX); each
    /// askEachTime TOTP capability yields an empty `.totp` placeholder the
    /// detail screen swaps for the Request control.
    nonisolated static func buildItem(origin: SharedOrigin, grant: AccessGrant,
                                      display: SharedDisplayEnvelope?,
                                      values: [String: Data]) -> VaultItem {
        var fields: [DynamicField] = []
        for fieldId in values.keys.sorted() {
            guard let data = values[fieldId],
                  let value = String(data: data, encoding: .utf8) else { continue }
            // Envelope metadata gives the field its real identity (username
            // renders visible, password masked, AutoFill kinds correct);
            // unknown/missing meta fails CLOSED into a masked secret.
            let meta = display?.fields?[fieldId]
            let kind = meta.flatMap { FieldKind(rawValue: $0.kind) } ?? .password
            let label = meta?.label.isEmpty == false ? meta!.label : appString("Shared value")
            fields.append(DynamicField(id: fieldId, label: label, kind: kind, value: value))
        }
        // No placeholder TOTP fields: the detail screen derives its Request
        // rows from the grant's capabilities, and an empty field would only
        // confuse list subtitles.
        if let host = display?.websiteHost, !host.isEmpty {
            // Stable id — a fresh UUID per refresh would needlessly
            // invalidate row identity.
            fields.append(DynamicField(id: "shared-website", label: appString("Website"),
                                       kind: .url, value: host))
        }
        let updatedAt = display.map { Date(timeIntervalSince1970: Double($0.updatedAtUnixMs) / 1000) }
            ?? Date(timeIntervalSince1970: Double(grant.createdAtUnixMs) / 1000)
        var item = VaultItem(id: origin.itemID, category: .login,
                             title: display?.title.isEmpty == false
                                ? display!.title : appString("Shared item"),
                             fields: fields,
                             createdAt: Date(timeIntervalSince1970: Double(grant.createdAtUnixMs) / 1000),
                             updatedAt: updatedAt)
        item.sharedOrigin = origin
        return item
    }

    private static func zoneID(for origin: SharedOrigin) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: origin.zoneName, ownerName: origin.ownerName)
    }

    /// Stable opaque per-install id for request metadata (not a secret) —
    /// resolved once at init so view bodies never write UserDefaults.
    let recipientDeviceId: String = {
        let key = "approval_recipient_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = ApprovalConfig.opaqueName()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()
}
