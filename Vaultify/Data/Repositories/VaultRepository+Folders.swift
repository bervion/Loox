import Foundation
import SwiftData

/// Folder ("Space") management, Recents queries, and tag aggregation. Kept in an
/// extension so the core item-CRUD file stays lean. Folder names are sealed under
/// the Vault Key, mirroring the item seal/open path.
extension VaultRepository {

    // MARK: Folder sealing (mirrors the item seal/open path)

    private func sealFolder(_ folder: Folder, key: SecureBytes) throws -> Data {
        try AESGCM.seal(JSONEncoder().encode(folder.secret), key: key)
    }

    private func decryptFolder(_ record: FolderRecord, key: SecureBytes) throws -> Folder {
        let plaintext = try AESGCM.open(record.sealed, key: key)
        let secret = try JSONDecoder().decode(FolderSecret.self, from: plaintext)
        return Folder(id: record.id,
                      name: secret.name,
                      iconAsset: record.iconAsset,
                      color: FolderColor(rawValue: record.colorRaw) ?? .gray,
                      sortIndex: record.sortIndex,
                      createdAt: record.createdAt,
                      updatedAt: record.updatedAt)
    }

    /// Decrypt all live folders, sorted by sort order then creation. Called from
    /// `reload()` while the Vault Key is in scope.
    func loadFolders(key: SecureBytes) -> [Folder] {
        let descriptor = FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.deletedAt == nil })
        guard let records = try? store.context.fetch(descriptor) else { return [] }
        return records
            .compactMap { try? decryptFolder($0, key: key) }
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    private func folderRecord(id: String) -> FolderRecord? {
        var descriptor = FetchDescriptor<FolderRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? store.context.fetch(descriptor).first
    }

    // MARK: Folder CRUD

    @discardableResult
    func addFolder(name: String, icon: String, color: FolderColor) throws -> String {
        guard let key = session.vaultKey else { throw AuthError.locked }
        let folder = Folder(name: name, iconAsset: icon, color: color,
                            sortIndex: (folders.map(\.sortIndex).max() ?? -1) + 1)
        let record = FolderRecord(id: folder.id,
                                  sealed: try sealFolder(folder, key: key),
                                  iconAsset: folder.iconAsset,
                                  colorRaw: folder.color.rawValue,
                                  sortIndex: folder.sortIndex,
                                  createdAt: folder.createdAt,
                                  updatedAt: folder.updatedAt)
        store.context.insert(record)
        try store.context.save()
        reload()
        return folder.id
    }

    func updateFolder(_ folder: Folder) throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        guard let record = folderRecord(id: folder.id) else { return }
        record.sealed = try sealFolder(folder, key: key)
        record.iconAsset = folder.iconAsset
        record.colorRaw = folder.color.rawValue
        record.sortIndex = folder.sortIndex
        record.updatedAt = .now
        record.dirty = true
        try store.context.save()
        reload()
    }

    /// Delete a folder. Member items are reassigned to Unfiled (folderId = nil,
    /// re-sealed) — never deleted. The folder itself gets a tombstone for sync.
    func deleteFolder(_ folder: Folder) throws {
        for item in items where item.folderId == folder.id {
            var moved = item
            moved.folderId = nil
            try update(moved)
        }
        guard let record = folderRecord(id: folder.id) else { return }
        record.deletedAt = .now
        record.dirty = true
        try store.context.save()
        reload()
    }

    /// Move an item into a folder (or out, with `nil`). Re-seals the item.
    func assign(_ item: VaultItem, toFolder folderId: String?) throws {
        var moved = item
        moved.folderId = folderId
        try update(moved)
    }

    // MARK: Counts & filtered accessors (live items only — trashed excluded)

    func itemCount(for folderId: String) -> Int {
        items.filter { $0.folderId == folderId }.count
    }

    var unfiledCount: Int { items.filter { $0.folderId == nil }.count }

    func items(inFolder folderId: String?) -> [VaultItem] {
        items.filter { $0.folderId == folderId }
    }

    // MARK: Recents

    func recentlyUsed(limit: Int) -> [VaultItem] {
        Array(items
            .filter { $0.lastUsedAt != nil }
            .sorted { ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            .prefix(limit))
    }

    // MARK: Tags (lightweight — stored inside each item's sealed payload)

    /// Distinct tags across live items with counts. Grouped case-insensitively
    /// (`#AWS` and `#aws` merge) but shown in the first-seen casing.
    func allTags() -> [(tag: String, count: Int)] {
        var grouped: [String: (display: String, count: Int)] = [:]
        for tag in items.flatMap(\.tags) {
            let key = tag.lowercased()
            if let existing = grouped[key] {
                grouped[key] = (existing.display, existing.count + 1)
            } else {
                grouped[key] = (tag, 1)
            }
        }
        return grouped.values
            .map { (tag: $0.display, count: $0.count) }
            .sorted { $0.count != $1.count
                ? $0.count > $1.count
                : $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending }
    }

    func items(withTag tag: String) -> [VaultItem] {
        let needle = tag.lowercased()
        return items.filter { $0.tags.contains { $0.lowercased() == needle } }
    }
}
