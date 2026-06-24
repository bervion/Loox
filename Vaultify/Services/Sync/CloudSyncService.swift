import Foundation
import CloudKit

/// Zero-knowledge CloudKit sync: only the already-sealed (AES-256-GCM) item
/// blobs and non-secret metadata are uploaded to the user's private database.
/// CloudKit never sees plaintext or the Vault Key. Last-writer-wins by `updatedAt`.
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

    func sync(reload: @escaping () -> Void) async {
        guard settings.iCloudSyncEnabled else { return }
        guard Self.isConfigured else {
            status = .error(appString("iCloud sync needs the iCloud capability enabled in Xcode."))
            return
        }
        status = .syncing
        do {
            _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
            try await push()
            try await pull()
            reload()
            status = .success(.now)
        } catch let error as CKError where error.code == .notAuthenticated {
            status = .error(appString("Sign in to iCloud to sync."))
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func push() async throws {
        try await pushItems()
        try await pushFolders()
    }

    private func pushItems() async throws {
        let dirty = store.allRecords().filter(\.dirty)
        guard !dirty.isEmpty else { return }
        let records = dirty.map(ckRecord(from:))
        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
        for (recordID, saveResult) in result.saveResults {
            if case .success(let saved) = saveResult, let local = store.record(id: recordID.recordName) {
                store.markSynced(local, changeTag: saved.recordChangeTag)
            }
        }
    }

    private func pushFolders() async throws {
        let dirty = store.allFolderRecords().filter(\.dirty)
        guard !dirty.isEmpty else { return }
        let records = dirty.map(ckFolderRecord(from:))
        let result = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys)
        for (recordID, saveResult) in result.saveResults {
            if case .success(let saved) = saveResult, let local = store.folderRecord(id: recordID.recordName) {
                store.markFolderSynced(local, changeTag: saved.recordChangeTag)
            }
        }
    }

    private func pull() async throws {
        try await pull(recordType: recordType, apply: apply)
        try await pull(recordType: folderRecordType, apply: applyFolder)
    }

    private func pull(recordType: String, apply: (CKRecord) -> Void) async throws {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let (matches, _) = try await database.records(
            matching: query, inZoneWith: zone.zoneID,
            desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults)
        for (_, recordResult) in matches {
            guard case .success(let record) = recordResult else { continue }
            apply(record)
        }
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
        ck["useCount"] = record.useCount as CKRecordValue
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
            useCount: record["useCount"] as? Int ?? 0,
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
}
