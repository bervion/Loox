import Foundation
import CloudKit

/// CloudKit sync of the user's private database. **Secrets are sealed** (AES-256-GCM
/// item/folder blobs; CloudKit never sees plaintext or the Vault Key), while a small
/// set of *organizational* metadata rides in cleartext columns so devices can merge
/// without unsealing: timestamps, favorite/pinned/archived flags, folder icon/color/
/// sort order. Content merges last-writer-wins by `updatedAt`; the column-only
/// pinned/archived toggles merge by their own `metaUpdatedAt` (see `VaultStore`).
@MainActor @Observable final class CloudSyncService {
    enum Status: Equatable {
        case idle, syncing, success(Date), error(String)
    }

    private(set) var status: Status = .idle

    private let store: VaultStore
    private let settings: SettingsStore
    // Lazy: created only when sync first runs, so launch never touches CloudKit
    // (avoids a trap when the iCloud container isn't provisioned/enabled).
    @ObservationIgnored private lazy var container = CKContainer(identifier: "iCloud.com.bervion.vaultify")
    private let zone = CKRecordZone(zoneName: "Vault")
    private let recordType = "VaultItem"
    private let folderRecordType = "VaultFolder"
    private let passkeyRecordType = "VaultPasskey"
    private let personaRecordType = "VaultPersona"
    private let aliasRecordType = "VaultEmailAlias"
    private let inboxRecordType = "VaultForwardingInbox"
    private let auditReportRecordType = "AuditReport"
    private let findingStateRecordType = "AuditFindingState"
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
            // still run, then the first push failure surfaces as the status.
            let pushError = await push()
            try await pull()
            reload()
            if let pushError { throw pushError }
            status = .success(.now)
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
    /// hit an undeployed `VaultPersona` type. Returns the FIRST error so the
    /// caller can surface it after everything ran.
    private func push() async -> Error? {
        var firstError: Error?
        do { try await pushItems() } catch { firstError = firstError ?? error }
        do { try await pushFolders() } catch { firstError = firstError ?? error }
        do { try await pushPasskeys() } catch { firstError = firstError ?? error }
        do { try await pushPersonas() } catch { firstError = firstError ?? error }
        do { try await pushAliases() } catch { firstError = firstError ?? error }
        do { try await pushInboxes() } catch { firstError = firstError ?? error }
        do { try await pushAuditReports() } catch { firstError = firstError ?? error }
        do { try await pushFindingStates() } catch { firstError = firstError ?? error }
        return firstError
    }

    /// One CloudKit modify operation caps out around 400 records / 2 MB. A big
    /// batch (large import + first sync) would fail the whole call — and since
    /// failures keep records dirty, the next sync retries the same oversized
    /// batch, forever. Every plane therefore pushes through this wrapper:
    /// bounded chunks, non-atomic saves so one rejected or oversized record
    /// fails only itself, successes marked before the first error is rethrown
    /// (the failed remainder stays dirty for the next run).
    private static let pushChunkSize = 200

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
            case self.recordType: self.apply(record)
            case self.folderRecordType: self.applyFolder(record)
            case self.passkeyRecordType: self.applyPasskey(record)
            case self.personaRecordType: self.applyPersona(record)
            case self.aliasRecordType: self.applyAlias(record)
            case self.inboxRecordType: self.applyInbox(record)
            case self.auditReportRecordType: self.applyAuditReport(record)
            case self.findingStateRecordType: self.applyFindingState(record)
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
        let ck = CKRecord(recordType: recordType, recordID: id)
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
        let ck = CKRecord(recordType: folderRecordType, recordID: id)
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
        let dirty = store.allPasskeyRecords().filter {
            $0.dirty && $0.envelopeSealed == nil && $0.id.utf8.count <= 255
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

    private func ckPasskeyRecord(from record: PasskeyRecord) -> CKRecord {
        let id = CKRecord.ID(recordName: record.id, zoneID: zone.zoneID)
        let ck = CKRecord(recordType: passkeyRecordType, recordID: id)
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

    private func applyPasskey(_ record: CKRecord) {
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
        let ck = CKRecord(recordType: personaRecordType, recordID: id)
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
        let ck = CKRecord(recordType: aliasRecordType, recordID: id)
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
        let ck = CKRecord(recordType: inboxRecordType, recordID: id)
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
        let ck = CKRecord(recordType: auditReportRecordType, recordID: id)
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
        let ck = CKRecord(recordType: findingStateRecordType, recordID: id)
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
