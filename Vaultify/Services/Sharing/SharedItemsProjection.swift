import CloudKit
import Foundation

/// Recipient-side shared items as first-class `VaultItem`s (V1.2 plan, V1/V2).
///
/// A PROJECTION, not storage: models are rebuilt from the accepted shared
/// zones (grant + display envelope + sealed shared values) and live only in
/// memory. They deliberately never touch `VaultStore` — vault-item sync,
/// backup, export, and Watchtower all read the store and must see zero shared
/// items. Revoke = the zone disappears = the item disappears. AutoFill is the
/// one deliberate exception (Phase 8): every refresh mirrors a flattened,
/// separately-sealed copy into `SharedCredentialsCache` for the extension.
@MainActor @Observable final class SharedItemsProjection {
    /// Projected items, title-sorted. Each carries `sharedOrigin`.
    private(set) var items: [VaultItem] = []
    /// True once a refresh has successfully listed the accepted zones —
    /// distinguishes "still loading after cold start" from "item is gone".
    private(set) var hasLoaded = false

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
        // Optimistic local removal: a concurrent shell refresh would make the
        // follow-up refresh below a single-flight no-op, leaving the departed
        // item on screen until the next trigger. Server truth already changed.
        items.removeAll { $0.id == itemId }
        requestModels = requestModels.filter { !$0.key.hasPrefix(origin.grantId + "|") }
        grants.removeValue(forKey: itemId)
        let cacheEntries = items.compactMap { item -> SharedCredentialEntry? in
            guard let grant = grants[item.id] else { return nil }
            return Self.cacheEntry(item: item, grant: grant)
        }
        try? SharedCredentialsCache.save(entries: cacheEntries, vaultKey: vaultKey)
        CredentialIdentityService.refreshShared(cacheEntries)
        persistSnapshot(vaultKey: vaultKey)
        await refresh(vaultKey: vaultKey)
    }

    func wipe() {
        hasLoaded = false
        items = []
        grants = [:]
        requestModels = [:]
    }

    // MARK: Sealed snapshot (instant re-hydration after unlock)

    /// The projection is memory-only and wiped on lock — without a snapshot,
    /// every unlock/cold start showed "no shared items" until a full CloudKit
    /// round trip finished (or indefinitely offline). Same at-rest model as
    /// `SharedCredentialsCache`: ciphertext under the Vault Key, survives a
    /// lock, cleared only by vault erase.
    private nonisolated struct Snapshot: Codable {
        var items: [VaultItem]
        var grants: [String: AccessGrant]
    }

    private static let snapshotVersion: UInt8 = 1
    private nonisolated static var snapshotURL: URL {
        SharedConfig.containerURL.appending(path: "shared-projection-snapshot.bin")
    }

    /// Re-hydrate the last known projection so lists show shared items the
    /// moment the vault unlocks; the network refresh then reconciles. No-op
    /// once anything is loaded. Best-effort: corruption/missing → stays empty.
    func seedFromSnapshot(vaultKey: [UInt8]) {
        guard !hasLoaded, items.isEmpty,
              let envelope = try? Data(contentsOf: Self.snapshotURL),
              envelope.first == Self.snapshotVersion,
              let plain = try? AESGCM.open(envelope.dropFirst(), key: vaultKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: plain),
              !snapshot.items.isEmpty else { return }
        items = snapshot.items
        grants = snapshot.grants
        hasLoaded = true
    }

    private func persistSnapshot(vaultKey: [UInt8]) {
        guard let plain = try? JSONEncoder().encode(Snapshot(items: items, grants: grants)),
              let sealed = try? AESGCM.seal(plain, key: vaultKey) else { return }
        var envelope = Data([Self.snapshotVersion])
        envelope.append(sealed)
        try? envelope.write(to: Self.snapshotURL, options: [.atomic, .completeFileProtection])
    }

    /// Vault erase only — a lock deliberately keeps the sealed snapshot.
    nonisolated static func clearPersisted() {
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    // MARK: Refresh (single-flight; triggers live on the unlocked shell)

    func refresh(vaultKey: [UInt8]) async {
        guard CloudSyncService.isConfigured, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        // Instant re-hydration first — the network reconcile below can take
        // seconds (or fail offline), and "empty until CloudKit answers" reads
        // as "my shared item is gone".
        seedFromSnapshot(vaultKey: vaultKey)
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
        // A cancelled refresh (lock / shell teardown mid-flight) surfaces as
        // per-zone "transient" errors with the projection already wiped — so
        // `built` is empty garbage, not truth. Committing it would ALSO
        // overwrite the AutoFill cache below with an empty list, silently
        // killing shared credentials in the extension until the next full
        // refresh. Bail out before touching any state.
        guard !Task.isCancelled else { return }
        items = built.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        grants = builtGrants
        hasLoaded = true
        // Drop machines whose grant rotated or vanished (fresh models next time).
        requestModels = requestModels.filter { key, _ in
            liveGrantIDs.contains(String(key.split(separator: "|")[0]))
        }
        // AutoFill sees none of the above — persist a flattened, Vault-Key-sealed
        // copy (survives lock; see SharedCredentialsCache) and refresh QuickType.
        // An empty `items` (last share left/revoked) overwrites with an empty
        // cache, which is exactly the "disappear" behavior Leave/revoke need.
        let cacheEntries = items.compactMap { item -> SharedCredentialEntry? in
            guard let grant = grants[item.id] else { return nil }
            return Self.cacheEntry(item: item, grant: grant)
        }
        try? SharedCredentialsCache.save(entries: cacheEntries, vaultKey: vaultKey)
        CredentialIdentityService.refreshShared(cacheEntries)
        persistSnapshot(vaultKey: vaultKey)
    }

    /// Flattens a projected item + its grant into the AutoFill cache shape.
    private static func cacheEntry(item: VaultItem, grant: AccessGrant) -> SharedCredentialEntry? {
        guard let origin = item.sharedOrigin else { return nil }
        let totpFieldId = grant.capabilities.first { $0.value.isAskEachTimeTOTP }?.key
        return SharedCredentialEntry(
            itemID: item.id, title: item.title,
            websiteHost: normalizedHost(item.urlField?.value),
            username: item.usernameField?.value.isEmpty == false ? item.usernameField?.value : nil,
            password: item.passwordField?.value.isEmpty == false ? item.passwordField?.value : nil,
            zoneName: origin.zoneName, ownerName: origin.ownerName, grantId: origin.grantId,
            askEachTimeTOTPFieldId: totpFieldId)
    }

    /// The cache's host feeds QuickType registration (`.domain`-type service
    /// identifiers) and the extension's site matching — both need a bare host.
    /// The owner may have shared their URL FIELD verbatim ("https://x.y/login"),
    /// which would never match a domain identifier.
    nonisolated static func normalizedHost(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let candidate = raw.contains("://") ? raw : "https://\(raw)"
        if let host = URL(string: candidate)?.host, !host.isEmpty { return host.lowercased() }
        return raw.lowercased()
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
        // Detail-screen field order (dictionary order is random): identity
        // first, then secrets, extras, website last.
        func rank(_ kind: FieldKind) -> Int {
            switch kind {
            case .username, .email: 0
            case .password: 1
            case .url: 9
            default: 2
            }
        }
        fields = fields.enumerated()
            .sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }
            .map(\.element)
        // No placeholder TOTP fields: the detail screen derives its Request
        // rows from the grant's capabilities, and an empty field would only
        // confuse list subtitles.
        // Envelope host is a FALLBACK — if the owner shared their URL field
        // itself, appending the host too would duplicate "Website".
        if !fields.contains(where: { $0.kind == .url }),
           let host = display?.websiteHost, !host.isEmpty {
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
