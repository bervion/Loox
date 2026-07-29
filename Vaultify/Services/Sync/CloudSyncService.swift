import Foundation
import CloudKit
import os

private let syncLog = Logger(subsystem: "com.bervion.vaultify", category: "cloud-sync")

/// CloudKit sync of the user's private database. **Secrets are sealed** (AES-256-GCM
/// item/folder blobs; CloudKit never sees plaintext or the Vault Key), while a small
/// set of *organizational* metadata rides in cleartext columns so devices can merge
/// without unsealing: timestamps, favorite/pinned/archived flags, folder icon/color/
/// sort order. Content merges last-writer-wins by `updatedAt`; the column-only
/// pinned/archived toggles merge by their own `metaUpdatedAt` (see `VaultStore`).
@MainActor @Observable final class CloudSyncService {
    enum Status: Equatable {
        case idle, syncing, success(Date)
        /// Transient failure: offline, throttled, iCloud signed out. Retrying clears it.
        case error(String)
        /// Permanent failure: a record type or field this app pushes is not deployed
        /// in the CloudKit environment this build talks to. Production has no
        /// just-in-time schema creation, so every retry fails identically until the
        /// schema is deployed — the UI must not read this as a network blip.
        case configurationError(String)
    }

    /// The record types this service pushes, one per plane. Planes are pushed and
    /// rejected independently, so a failure has to name the plane it came from: an
    /// undeployed record type fails only its own plane while everything else keeps
    /// syncing, and collapsing all eight into one message is what let an undeployed
    /// `VaultPasskey` type look like an ordinary network error for two releases.
    enum Plane: String, CaseIterable {
        case items = "VaultItem"
        case folders = "VaultFolder"
        case passkeys = "VaultPasskey"
        case personas = "VaultPersona"
        case aliases = "VaultEmailAlias"
        case inboxes = "VaultForwardingInbox"
        case auditReports = "AuditReport"
        case findingStates = "AuditFindingState"

        var recordType: String { rawValue }

        /// Name shown in the sync status, in the feature's own vocabulary.
        var displayName: String {
            switch self {
            case .items: return appString("Items")
            case .folders: return appString("Spaces")
            case .passkeys: return appString("Passkeys")
            case .personas: return appString("Personas")
            case .aliases: return appString("Email aliases")
            case .inboxes: return appString("Forwarding inboxes")
            case .auditReports: return appString("Audit history")
            case .findingStates: return appString("Audit findings")
            }
        }
    }

    /// A push failure tagged with the plane that produced it.
    private struct PlaneFailure: Error {
        let plane: Plane
        let underlying: Error
    }

    private(set) var status: Status = .idle

    /// Live passkeys this device can never upload because their credential id
    /// exceeds CloudKit's record-name cap (see `pushPasskeys`). Surfaced in
    /// Settings so the exclusion is visible instead of silent.
    private(set) var passkeysExcludedFromSync = 0

    private let store: VaultStore
    private let settings: SettingsStore
    // Lazy: created only when sync first runs, so launch never touches CloudKit
    // (avoids a trap when the iCloud container isn't provisioned/enabled).
    @ObservationIgnored private lazy var container = CKContainer(identifier: "iCloud.com.bervion.vaultify")
    private let zone = CKRecordZone(zoneName: "Vault")
    private var database: CKDatabase { container.privateCloudDatabase }

    init(store: VaultStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    /// Whether iCloud (CloudKit) is enabled for this build. Compile-gated because
    /// the iCloud entitlement crashes unprovisioned/simulator builds at launch and
    /// iOS has no API to read our own entitlements at runtime. To turn sync on:
    /// (1) add the iCloud capability (CloudKit) to the app target in Xcode, and
    /// (2) add `VAULTIFY_ICLOUD` to Swift Active Compilation Conditions.
    /// Off by default → sync never touches CloudKit (no launch crash, no noisy log).
    static var isConfigured: Bool {
        #if VAULTIFY_ICLOUD
        return true
        #else
        return false
        #endif
    }

    /// True while this process hosts XCTest. The test host builds with
    /// `CODE_SIGNING_ALLOWED=NO`, and `CKContainer.init` TRAPS (SIGTRAP) without the
    /// iCloud entitlement — any repository write in a test debounces a background sync
    /// and intermittently crashes the whole run. Sync must never start under tests.
    nonisolated static let isHostingUnitTests =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    func sync(reload: @escaping () -> Void) async {
        guard !Self.isHostingUnitTests else { return }
        guard settings.iCloudSyncEnabled else { return }
        guard Self.isConfigured else {
            status = .error(appString("iCloud sync needs the iCloud capability enabled in Xcode."))
            return
        }
        status = .syncing
        do {
            _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
            // Push errors are collected, not thrown mid-way: pull + reload
            // still run, then the failing plane surfaces as the status.
            let pushFailure = await push()
            try await pull()
            reload()
            if let pushFailure { throw pushFailure }
            status = .success(.now)
        } catch let failure as PlaneFailure {
            status = Self.status(for: failure)
        } catch let error as CKError where error.code == .notAuthenticated {
            status = .error(appString("Sign in to iCloud to sync."))
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Best-effort remote wipe for "Erase Vault": deleting the zone drops every
    /// synced record — sealed items/folders, the recovery-key envelope, and any
    /// pairing hand-offs — so the printed Emergency Kit can no longer resurrect an
    /// "erased" vault from iCloud, and a re-created vault never pulls undecryptable
    /// ghosts sealed under the old key. Offline/erased-signed-out is tolerated (the
    /// local wipe still proceeds; the cloud copy then outlives until next sign-in).
    func eraseRemote() async {
        guard Self.isConfigured else { return }
        _ = try? await database.modifyRecordZones(saving: [], deleting: [zone.zoneID])
        // The push subscription pointed at the deleted zone; drop it and forget the
        // local marker so a future vault re-subscribes cleanly.
        _ = try? await database.modifySubscriptions(saving: [], deleting: [SyncPushService.subscriptionID])
        SyncPushService.clearLocalFlag()
        // The delta cursor died with the zone — a future vault must full-fetch.
        savedChangeToken = nil
    }

    /// Push every plane, isolating failures: one record type the server
    /// rejects (typically a type not yet deployed to the PRODUCTION CloudKit
    /// schema, where just-in-time creation is off) must not starve the other
    /// planes or the pull — that coupling once kept fresh installs from ever
    /// uploading items or the recovery envelope after the auto-seeded persona
    /// hit an undeployed `VaultPersona` type. Returns one failure, tagged with
    /// its plane, so the caller can name what stopped syncing.
    private func push() async -> PlaneFailure? {
        var reported: PlaneFailure?
        func run(_ plane: Plane, _ body: () async throws -> Void) async {
            do {
                try await body()
            } catch {
                let schema = Self.isSchemaFailure(error)
                syncLog.error("push-failed plane=\(plane.recordType, privacy: .public) schema=\(schema, privacy: .public) code=\(Self.diagnosticCode(error), privacy: .public)")
                // A schema failure outranks whatever came before it: it never
                // clears on its own, so a network blip in an earlier plane must
                // not be the one message the user sees.
                let outranks = reported.map { schema && !Self.isSchemaFailure($0.underlying) } ?? true
                if outranks { reported = PlaneFailure(plane: plane, underlying: error) }
            }
        }
        await run(.items) { try await pushItems() }
        await run(.folders) { try await pushFolders() }
        await run(.passkeys) { try await pushPasskeys() }
        await run(.personas) { try await pushPersonas() }
        await run(.aliases) { try await pushAliases() }
        await run(.inboxes) { try await pushInboxes() }
        await run(.auditReports) { try await pushAuditReports() }
        await run(.findingStates) { try await pushFindingStates() }
        return reported
    }

    /// A rejection the server will repeat forever: the record type or one of its
    /// fields is not deployed in this CloudKit environment, so the write is refused
    /// on its face (`invalidArguments` carries "unknown record type" and field-type
    /// mismatches; `serverRejectedRequest` a request shape the server will not take),
    /// and no amount of retrying deploys a schema. Everything else — offline,
    /// throttled, zone busy, signed out — is transient and clears by itself. A
    /// unique-constraint violation is deliberately NOT here: this app declares no
    /// unique index, so treating it as a deployment gap would only mislabel data.
    nonisolated static func isSchemaFailure(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .invalidArguments, .serverRejectedRequest:
            return true
        case .partialFailure:
            // Non-atomic saves report per-record rejections here, which is where a
            // missing record type actually lands during a batch push.
            return ckError.partialErrorsByItemID?.values.contains(where: isSchemaFailure) ?? false
        default:
            return false
        }
    }

    /// Log-safe identity of a failure: error domain and code, plus the codes nested
    /// in a partial failure. The full description embeds CloudKit record names, and
    /// a passkey record name IS the credential id — it must never be logged public.
    private nonisolated static func diagnosticCode(_ error: Error) -> String {
        let ns = error as NSError
        var text = "\(ns.domain)/\(ns.code)"
        let inner = (error as? CKError)?.partialErrorsByItemID?.values
            .map { ($0 as NSError).code } ?? []
        if !inner.isEmpty {
            text += " inner=" + Set(inner).sorted().map { String($0) }.joined(separator: ",")
        }
        return text
    }

    private static func status(for failure: PlaneFailure) -> Status {
        let plane = failure.plane.displayName
        // A signed-out account reads the same whichever call noticed it first, and
        // the plane it happened to hit is noise next to the one action that fixes it.
        if let ckError = failure.underlying as? CKError, ckError.code == .notAuthenticated {
            return .error(appString("Sign in to iCloud to sync."))
        }
        guard isSchemaFailure(failure.underlying) else {
            return .error(appString("\(plane) didn’t finish syncing. \(failure.underlying.localizedDescription)"))
        }
        // The record type stays in the copy on purpose: it is the one detail that
        // turns a user's screenshot into an actionable CloudKit console fix. The
        // wording says "rejects", not "is missing" — a rejected request shape is
        // not always an absent type, and the banner must not diagnose past what
        // the server actually told us.
        return .configurationError(
            appString("\(plane) can’t sync. iCloud rejects the \(failure.plane.recordType) records this app sends, so retrying won’t fix it."))
    }

    /// One CloudKit modify operation caps out around 400 records / 2 MB. A big
    /// batch (large import + first sync) would fail the whole call — and since
    /// failures keep records dirty, the next sync retries the same oversized
    /// batch, forever. Every plane therefore pushes through this wrapper:
    /// bounded chunks, non-atomic saves so one rejected or oversized record
    /// fails only itself, successes marked before the first error is rethrown
    /// (the failed remainder stays dirty for the next run).
    private static let pushChunkSize = 200

    /// CloudKit's hard cap on a `CKRecord.ID` record name. A record whose name is
    /// longer cannot exist server-side at all, so those rows can only stay local.
    static let maxRecordNameBytes = 255

    private func modifyInChunks(saving records: [CKRecord],
                                markSuccess: (CKRecord.ID, CKRecord) -> Void) async throws {
        var firstError: Error?
        var start = 0
        while start < records.count {
            let chunk = Array(records[start ..< min(start + Self.pushChunkSize, records.count)])
            start += Self.pushChunkSize
            do {
                let result = try await database.modifyRecords(
                    saving: chunk, deleting: [], savePolicy: .changedKeys, atomically: false)
                for (recordID, saveResult) in result.saveResults {
                    switch saveResult {
                    case .success(let saved): markSuccess(recordID, saved)
                    case .failure(let error): firstError = firstError ?? error
                    }
                }
            } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    private func pushItems() async throws {
        let dirty = store.allRecords().filter(\.dirty)
        guard !dirty.isEmpty else { return }
        // Snapshot each record's timestamps BEFORE the await: `modifyRecords` is a
        // suspension point, and an edit made mid-flight must stay dirty (markSynced
        // clears the flag only when the record is unchanged since this snapshot).
        let snapshots = Dictionary(uniqueKeysWithValues: dirty.map {
            ($0.id, (updatedAt: $0.updatedAt, metaUpdatedAt: $0.metaUpdatedAt))
        })
        let records = dirty.map(ckRecord(from:))
        try await modifyInChunks(saving: records) { recordID, saved in
            if let local = store.record(id: recordID.recordName),
               let snapshot = snapshots[recordID.recordName] {
                store.markSynced(local, changeTag: saved.recordChangeTag,
                                 snapshotUpdatedAt: snapshot.updatedAt,
                                 snapshotMetaUpdatedAt: snapshot.metaUpdatedAt)
            }
        }
    }

    private func pushFolders() async throws {
        let dirty = store.allFolderRecords().filter(\.dirty)
        guard !dirty.isEmpty else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: dirty.map { ($0.id, $0.updatedAt) })
        let records = dirty.map(ckFolderRecord(from:))
        try await modifyInChunks(saving: records) { recordID, saved in
            if let local = store.folderRecord(id: recordID.recordName),
               let snapshot = snapshots[recordID.recordName] {
                store.markFolderSynced(local, changeTag: saved.recordChangeTag,
                                       snapshotUpdatedAt: snapshot)
            }
        }
    }

    /// Pull via zone-changes delta fetch — the canonical CloudKit sync primitive.
    /// Deliberately NOT `CKQuery`: a TRUEPREDICATE query needs the `recordName`
    /// system field marked Queryable in the CloudKit schema (a manual console index
    /// that must be re-added per environment; missing it fails every pull with
    /// "Field 'recordName' is not marked queryable"). Zone changes need no index,
    /// page via `moreComing`, and the persisted server change token means later
    /// syncs download only what actually changed. Token loop + expiry recovery
    /// live in the shared `ZoneDeltaFetch` (also used by the approval path).
    /// `deletions` are unused by design: vault deletions travel as soft
    /// tombstones (deletedAt) on modified records, never as CK deletes.
    private func pull() async throws {
        try await ZoneDeltaFetch.pull(database: database, zoneID: zone.zoneID,
                                      cursor: changeCursor) { record in
            switch record.recordType {
            case Plane.items.recordType: self.apply(record)
            case Plane.folders.recordType: self.applyFolder(record)
            case Plane.passkeys.recordType: self.applyPasskey(record)
            case Plane.personas.recordType: self.applyPersona(record)
            case Plane.aliases.recordType: self.applyAlias(record)
            case Plane.inboxes.recordType: self.applyInbox(record)
            case Plane.auditReports.recordType: self.applyAuditReport(record)
            case Plane.findingStates.recordType: self.applyFindingState(record)
            // Device registry + sign-out markers: mirrored locally so the
            // Devices list and the remote sign-out check need no CKQuery.
            case DeviceRegistryService.recordType,
                 DeviceRegistryService.revocationRecordType:
                DeviceRegistryMirror.apply(record)
            // Key-escrow records share the zone but aren't vault data.
            default: break
            }
        }
    }

    // MARK: Server change token (delta-pull cursor, device-local)

    /// Same UserDefaults key + archive format as always — adopting the shared
    /// cursor changes no persisted state.
    private let changeCursor = ChangeTokenCursor(key: "cloudkit_vault_zone_change_token")

    private var savedChangeToken: CKServerChangeToken? {
        get { changeCursor.token }
        set { changeCursor.token = newValue }
    }

    private func ckRecord(from record: ItemRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zone.zoneID)
        let ck = CKRecord(recordType: Plane.items.recordType, recordID: id)
        ck["sealed"] = record.sealed as CKRecordValue
        ck["createdAt"] = record.createdAt as CKRecordValue
        ck["updatedAt"] = record.updatedAt as CKRecordValue
        ck["favorite"] = (record.favorite ? 1 : 0) as CKRecordValue
        ck["pinned"] = (record.pinned ? 1 : 0) as CKRecordValue
        ck["archived"] = (record.archived ? 1 : 0) as CKRecordValue
        ck["metaUpdatedAt"] = record.metaUpdatedAt as CKRecordValue
        // `useCount`/`lastUsedAt` are deliberately NOT uploaded: they're device-local
        // usage telemetry (Recents / Frequently Used), and keeping them off CloudKit
        // also removes a plaintext usage-frequency signal from the cloud record.
        ck["isDefaultIdentity"] = (record.isDefaultIdentity ? 1 : 0) as CKRecordValue
        if let avatarSealed = record.avatarSealed { ck["avatarSealed"] = avatarSealed as CKRecordValue }
        if let trashedAt = record.trashedAt { ck["trashedAt"] = trashedAt as CKRecordValue }
        if let deletedAt = record.deletedAt { ck["deletedAt"] = deletedAt as CKRecordValue }
        return ck
    }

    private func apply(_ record: CKRecord) {
        guard let sealed = record["sealed"] as? Data,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else { return }
        store.upsertFromRemote(
            id: record.recordID.recordName, sealed: sealed,
            favorite: (record["favorite"] as? Int ?? 0) == 1,
            trashedAt: record["trashedAt"] as? Date,
            deletedAt: record["deletedAt"] as? Date,
            createdAt: createdAt, updatedAt: updatedAt,
            pinned: (record["pinned"] as? Int ?? 0) == 1,
            archived: (record["archived"] as? Int ?? 0) == 1,
            // Records written before the meta timestamp existed carry none — treat as
            // ancient so any local toggle wins.
            metaUpdatedAt: record["metaUpdatedAt"] as? Date ?? .distantPast,
            isDefaultIdentity: (record["isDefaultIdentity"] as? Int ?? 0) == 1,
            avatarSealed: record["avatarSealed"] as? Data,
            changeTag: record.recordChangeTag)
    }

    private func ckFolderRecord(from record: FolderRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zone.zoneID)
        let ck = CKRecord(recordType: Plane.folders.recordType, recordID: id)
        ck["sealed"] = record.sealed as CKRecordValue
        ck["iconAsset"] = record.iconAsset as CKRecordValue
        ck["colorRaw"] = record.colorRaw as CKRecordValue
        ck["sortIndex"] = record.sortIndex as CKRecordValue
        ck["createdAt"] = record.createdAt as CKRecordValue
        ck["updatedAt"] = record.updatedAt as CKRecordValue
        if let deletedAt = record.deletedAt { ck["deletedAt"] = deletedAt as CKRecordValue }
        return ck
    }

    private func applyFolder(_ record: CKRecord) {
        guard let sealed = record["sealed"] as? Data,
              let iconAsset = record["iconAsset"] as? String,
              let colorRaw = record["colorRaw"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else { return }
        store.upsertFolderFromRemote(
            id: record.recordID.recordName, sealed: sealed,
            iconAsset: iconAsset, colorRaw: colorRaw,
            sortIndex: (record["sortIndex"] as? Int) ?? 0,
            deletedAt: record["deletedAt"] as? Date,
            createdAt: createdAt, updatedAt: updatedAt,
            changeTag: record.recordChangeTag)
    }

    private func pushPasskeys() async throws {
        // Locked-write staging (`envelopeSealed != nil`) never syncs — only
        // this device's envelope key can promote it to a sealed record; the
        // unlock migration marks it dirty at that moment. The id-length guard
        // covers CKRecord's 255-char record-name cap: every Vaultify-minted
        // credential id is 22 chars, but iOS 26 credential exchange can import
        // foreign ids up to 1024 bytes — those stay device-local (and in
        // encrypted exports) instead of crashing the plane; revisit with a
        // hashed-name scheme if real imports ever hit this.
        let all = store.allPasskeyRecords()
        // The exclusion is permanent for those credentials, so it is counted (and
        // logged once per change) instead of being dropped on the floor. Tombstones
        // are left out: a deleted credential staying local is the intended outcome,
        // and counting it would warn about passkeys the user already removed.
        let excluded = all.filter {
            $0.deletedAt == nil && $0.id.utf8.count > Self.maxRecordNameBytes
        }.count
        if excluded != passkeysExcludedFromSync {
            if excluded > 0 {
                syncLog.notice("passkeys-excluded-from-sync count=\(excluded, privacy: .public) reason=record-name-cap")
            }
            passkeysExcludedFromSync = excluded
        }
        let dirty = all.filter {
            $0.dirty && $0.envelopeSealed == nil && $0.id.utf8.count <= Self.maxRecordNameBytes
        }
        guard !dirty.isEmpty else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: dirty.map { ($0.id, $0.updatedAt) })
        let records = dirty.map(ckPasskeyRecord(from:))
        try await modifyInChunks(saving: records) { recordID, saved in
            if let local = store.passkeyRecord(id: recordID.recordName),
               let snapshot = snapshots[recordID.recordName] {
                store.markPasskeySynced(local, changeTag: saved.recordChangeTag,
                                        snapshotUpdatedAt: snapshot)
            }
        }
    }

    /// Internal, not private: the field names and types below ARE the contract the
    /// deployed CloudKit schema must match, and a mapping test pins them.
    func ckPasskeyRecord(from record: PasskeyRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zone.zoneID)
        let ck = CKRecord(recordType: Plane.passkeys.recordType, recordID: id)
        // Every field is ALWAYS assigned: `.changedKeys` transmits only the
        // keys set on this fresh CKRecord, so an omitted-when-nil optional
        // could never be CLEARED server-side — a tombstone couldn't wipe the
        // cloud blob, and a revived credential (backup re-import) couldn't
        // clear its cloud tombstone, permanently diverging devices. Absence
        // is encoded in-band instead: empty Data / 0 ms.
        ck["sealed"] = record.sealed as CKRecordValue
        ck["largeBlobSealed"] = (record.largeBlobSealed ?? Data()) as CKRecordValue
        ck["createdAt"] = record.createdAt as CKRecordValue
        ck["updatedAt"] = record.updatedAt as CKRecordValue
        let deletedAtMs = record.deletedAt.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
        ck["deletedAtMs"] = deletedAtMs as CKRecordValue
        return ck
    }

    func applyPasskey(_ record: CKRecord) {
        guard let sealed = record["sealed"] as? Data,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else { return }
        let deletedAtMs = (record["deletedAtMs"] as? Int64) ?? 0
        store.upsertPasskeyFromRemote(
            id: record.recordID.recordName, sealed: sealed,
            largeBlobSealed: record["largeBlobSealed"] as? Data,
            deletedAt: deletedAtMs > 0
                ? Date(timeIntervalSince1970: TimeInterval(deletedAtMs) / 1000) : nil,
            createdAt: createdAt, updatedAt: updatedAt,
            changeTag: record.recordChangeTag)
    }

    private func pushPersonas() async throws {
        let dirty = store.allPersonaRecords().filter(\.dirty)
        guard !dirty.isEmpty else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: dirty.map { ($0.id, $0.updatedAt) })
        let records = dirty.map(ckPersonaRecord(from:))
        try await modifyInChunks(saving: records) { recordID, saved in
            if let local = store.personaRecord(id: recordID.recordName),
               let snapshot = snapshots[recordID.recordName] {
                store.markPersonaSynced(local, changeTag: saved.recordChangeTag,
                                        snapshotUpdatedAt: snapshot)
            }
        }
    }

    private func ckPersonaRecord(from record: PersonaRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zone.zoneID)
        let ck = CKRecord(recordType: Plane.personas.recordType, recordID: id)
        ck["sealed"] = record.sealed as CKRecordValue
        ck["isDefault"] = (record.isDefault ? 1 : 0) as CKRecordValue
        ck["sortIndex"] = record.sortIndex as CKRecordValue
        ck["createdAt"] = record.createdAt as CKRecordValue
        ck["updatedAt"] = record.updatedAt as CKRecordValue
        if let deletedAt = record.deletedAt { ck["deletedAt"] = deletedAt as CKRecordValue }
        return ck
    }

    private func applyPersona(_ record: CKRecord) {
        guard let sealed = record["sealed"] as? Data,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else { return }
        store.upsertPersonaFromRemote(
            id: record.recordID.recordName, sealed: sealed,
            isDefault: (record["isDefault"] as? Int ?? 0) == 1,
            sortIndex: (record["sortIndex"] as? Int) ?? 0,
            deletedAt: record["deletedAt"] as? Date,
            createdAt: createdAt, updatedAt: updatedAt,
            changeTag: record.recordChangeTag)
    }

    private func pushAliases() async throws {
        let dirty = store.allAliasRecords().filter(\.dirty)
        guard !dirty.isEmpty else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: dirty.map { ($0.id, $0.updatedAt) })
        let records = dirty.map(ckAliasRecord(from:))
        try await modifyInChunks(saving: records) { recordID, saved in
            if let local = store.aliasRecord(id: recordID.recordName),
               let snapshot = snapshots[recordID.recordName] {
                store.markAliasSynced(local, changeTag: saved.recordChangeTag, snapshotUpdatedAt: snapshot)
            }
        }
    }

    private func ckAliasRecord(from record: EmailAliasRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zone.zoneID)
        let ck = CKRecord(recordType: Plane.aliases.recordType, recordID: id)
        ck["sealed"] = record.sealed as CKRecordValue
        ck["sortIndex"] = record.sortIndex as CKRecordValue
        ck["createdAt"] = record.createdAt as CKRecordValue
        ck["updatedAt"] = record.updatedAt as CKRecordValue
        if let deletedAt = record.deletedAt { ck["deletedAt"] = deletedAt as CKRecordValue }
        return ck
    }

    private func applyAlias(_ record: CKRecord) {
        guard let sealed = record["sealed"] as? Data,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else { return }
        store.upsertAliasFromRemote(
            id: record.recordID.recordName, sealed: sealed,
            sortIndex: (record["sortIndex"] as? Int) ?? 0,
            deletedAt: record["deletedAt"] as? Date,
            createdAt: createdAt, updatedAt: updatedAt,
            changeTag: record.recordChangeTag)
    }

    private func pushInboxes() async throws {
        let dirty = store.allInboxRecords().filter(\.dirty)
        guard !dirty.isEmpty else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: dirty.map { ($0.id, $0.updatedAt) })
        let records = dirty.map(ckInboxRecord(from:))
        try await modifyInChunks(saving: records) { recordID, saved in
            if let local = store.inboxRecord(id: recordID.recordName),
               let snapshot = snapshots[recordID.recordName] {
                store.markInboxSynced(local, changeTag: saved.recordChangeTag, snapshotUpdatedAt: snapshot)
            }
        }
    }

    private func ckInboxRecord(from record: ForwardingInboxRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zone.zoneID)
        let ck = CKRecord(recordType: Plane.inboxes.recordType, recordID: id)
        ck["sealed"] = record.sealed as CKRecordValue
        ck["sortIndex"] = record.sortIndex as CKRecordValue
        ck["createdAt"] = record.createdAt as CKRecordValue
        ck["updatedAt"] = record.updatedAt as CKRecordValue
        if let deletedAt = record.deletedAt { ck["deletedAt"] = deletedAt as CKRecordValue }
        return ck
    }

    private func applyInbox(_ record: CKRecord) {
        guard let sealed = record["sealed"] as? Data,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else { return }
        store.upsertInboxFromRemote(
            id: record.recordID.recordName, sealed: sealed,
            sortIndex: (record["sortIndex"] as? Int) ?? 0,
            deletedAt: record["deletedAt"] as? Date,
            createdAt: createdAt, updatedAt: updatedAt,
            changeTag: record.recordChangeTag)
    }

    // MARK: Audit reports + finding states (sealed audit metadata; folder-pattern LWW)

    private func pushAuditReports() async throws {
        let dirty = store.allAuditReportRecords().filter(\.dirty)
        guard !dirty.isEmpty else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: dirty.map { ($0.id, $0.updatedAt) })
        let records = dirty.map(ckAuditReportRecord(from:))
        try await modifyInChunks(saving: records) { recordID, saved in
            if let local = store.auditReportRecord(id: recordID.recordName),
               let snapshot = snapshots[recordID.recordName] {
                store.markAuditReportSynced(local, changeTag: saved.recordChangeTag,
                                            snapshotUpdatedAt: snapshot)
            }
        }
    }

    private func ckAuditReportRecord(from record: AuditReportRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zone.zoneID)
        let ck = CKRecord(recordType: Plane.auditReports.recordType, recordID: id)
        ck["sealed"] = record.sealed as CKRecordValue
        ck["completedAt"] = record.completedAt as CKRecordValue
        ck["createdAt"] = record.createdAt as CKRecordValue
        ck["updatedAt"] = record.updatedAt as CKRecordValue
        if let personaID = record.personaID { ck["personaID"] = personaID as CKRecordValue }
        if let deletedAt = record.deletedAt { ck["deletedAt"] = deletedAt as CKRecordValue }
        return ck
    }

    private func applyAuditReport(_ record: CKRecord) {
        guard let sealed = record["sealed"] as? Data,
              let completedAt = record["completedAt"] as? Date,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else { return }
        store.upsertAuditReportFromRemote(
            id: record.recordID.recordName,
            personaID: record["personaID"] as? String,
            sealed: sealed, completedAt: completedAt,
            deletedAt: record["deletedAt"] as? Date,
            createdAt: createdAt, updatedAt: updatedAt,
            changeTag: record.recordChangeTag)
    }

    private func pushFindingStates() async throws {
        let dirty = store.allFindingStateRecords().filter(\.dirty)
        guard !dirty.isEmpty else { return }
        let snapshots = Dictionary(uniqueKeysWithValues: dirty.map { ($0.id, $0.updatedAt) })
        let records = dirty.map(ckFindingStateRecord(from:))
        try await modifyInChunks(saving: records) { recordID, saved in
            if let local = store.findingStateRecord(id: recordID.recordName),
               let snapshot = snapshots[recordID.recordName] {
                store.markFindingStateSynced(local, changeTag: saved.recordChangeTag,
                                             snapshotUpdatedAt: snapshot)
            }
        }
    }

    private func ckFindingStateRecord(from record: FindingStateRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zone.zoneID)
        let ck = CKRecord(recordType: Plane.findingStates.recordType, recordID: id)
        ck["sealed"] = record.sealed as CKRecordValue
        ck["status"] = record.status as CKRecordValue
        ck["createdAt"] = record.createdAt as CKRecordValue
        ck["updatedAt"] = record.updatedAt as CKRecordValue
        if let personaID = record.personaID { ck["personaID"] = personaID as CKRecordValue }
        if let deletedAt = record.deletedAt { ck["deletedAt"] = deletedAt as CKRecordValue }
        return ck
    }

    private func applyFindingState(_ record: CKRecord) {
        guard let sealed = record["sealed"] as? Data,
              let status = record["status"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else { return }
        store.upsertFindingStateFromRemote(
            id: record.recordID.recordName,
            personaID: record["personaID"] as? String,
            sealed: sealed, status: status,
            deletedAt: record["deletedAt"] as? Date,
            createdAt: createdAt, updatedAt: updatedAt,
            changeTag: record.recordChangeTag)
    }
}
