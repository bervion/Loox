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

    /// The Space a new item defaults into when the caller supplies no context.
    /// Single source for the "primary Space" heuristic so it can later resolve to
    /// the active identity's chosen primary Space by editing only this accessor —
    /// call sites never change. V1 = lowest-sortIndex folder (`folders` is already
    /// sorted by `(sortIndex, createdAt)`); `nil` when no folders exist (Unfiled world).
    var primarySpaceId: String? { folders.first?.id }

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
        noteLocalMutation()
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
        noteLocalMutation()
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
        // Tombstone must bump `updatedAt` or the pull LWW gate drops the deletion on
        // the other device (and a later edit there resurrects the folder).
        record.updatedAt = .now
        record.dirty = true
        try store.context.save()
        reload()
        noteLocalMutation()
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

    // MARK: Home accessors (live items only — archived/trashed already excluded)

    var pinnedItems: [VaultItem] { items.filter(\.pinned) }

    func frequentlyUsed(limit: Int) -> [VaultItem] {
        Array(items.filter { $0.useCount > 0 }.sorted { $0.useCount > $1.useCount }.prefix(limit))
    }
    func recentlyCreated(limit: Int) -> [VaultItem] {
        Array(items.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }
    func recentlyModified(limit: Int) -> [VaultItem] {
        Array(items.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    // MARK: Home DS section queries (folder-scoped)

    /// Scoped set of live items for a folder filter. nil = all folders.
    private func scoped(_ folderId: String?) -> [VaultItem] {
        guard let folderId else { return items }
        return items.filter { $0.folderId == folderId }
    }

    /// Favorite items, optionally scoped to a folder, sorted alphabetically.
    func favorites(folder folderId: String?) -> [VaultItem] {
        scoped(folderId).filter(\.favorite)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// All live items, optionally scoped, pinned items first then by updatedAt.
    func allItems(folder folderId: String?) -> [VaultItem] {
        scoped(folderId).sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    /// Items that have a non-empty TOTP field, optionally scoped to a folder.
    func totpItems(folder folderId: String?) -> [VaultItem] {
        scoped(folderId).filter { $0.totpField != nil }
    }

    /// Items needing attention, optionally scoped to a folder, capped at `limit`.
    func itemsNeedingAttention(folder folderId: String?, limit: Int = 4) -> [VaultItem] {
        let source: [VaultItem] = folderId == nil ? items : items.filter { $0.folderId == folderId }
        typealias Ranked = (item: VaultItem, order: Int)
        var ranked: [Ranked] = []
        for item in source {
            let status = RotationStatus.evaluate(
                rotateDays: item.rotateDays,
                passwordChangedAt: item.passwordChangedAt,
                createdAt: item.createdAt)
            let reason = RotationStatus.attentionReason(status: status, isWeak: item.hasWeakPassword)
            switch reason {
            case .overdue: ranked.append((item, 0))
            case .weak:    ranked.append((item, 1))
            case .soon:    ranked.append((item, 2))
            case .stale:   ranked.append((item, 3))
            case .none:    break
            }
        }
        return ranked.sorted { $0.order < $1.order }.prefix(limit).map(\.item)
    }

    // MARK: Category, lookup & search

    func items(ofCategory category: ItemCategory) -> [VaultItem] {
        items.filter { $0.category == category }
    }
    func count(forCategory category: ItemCategory) -> Int {
        items.filter { $0.category == category }.count
    }

    /// Live + archived lookup (so an item opened from Archive still resolves).
    func item(id: String) -> VaultItem? {
        items.first { $0.id == id }
            ?? archived.first { $0.id == id }
            ?? trashed.first { $0.id == id }
    }

    /// Scope-aware smart search: every space-separated token must appear in the
    /// item's searchable text (title/fields/tags). Scope handling:
    /// - `.thisSpace(id)` filters to that folder by strict id equality FIRST and
    ///   does not match on any Space name (matching another Space's name would
    ///   contradict the scope). A stale id therefore yields empty, never the
    ///   global set.
    /// - `.allSpaces` also matches an item's own Space name (e.g. "github work").
    /// - `.sharedWithMe` returns empty here — shared projections aren't vault
    ///   items; the search surface supplies them for that scope.
    ///
    /// Unfiled (`folderId == nil`) items are included under `.allSpaces` and
    /// excluded under any `.thisSpace` (no id match). They stay reachable via the
    /// Unfiled route and All-Spaces search, so they never vanish from the app.
    func search(_ query: String, scope: SpaceScope) -> [VaultItem] {
        let tokens = query.trimmingCharacters(in: .whitespaces).lowercased()
            .split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return [] }
        switch scope {
        case .sharedWithMe:
            return []
        case .thisSpace(let id):
            return items.filter { item in
                item.folderId == id && tokens.allSatisfy { item.searchText.contains($0) }
            }
        case .allSpaces:
            let names = Dictionary(folders.map { ($0.id, $0.name.lowercased()) }, uniquingKeysWith: { a, _ in a })
            return items.filter { item in
                let hay = item.searchText + " " + (item.folderId.flatMap { names[$0] } ?? "")
                return tokens.allSatisfy { hay.contains($0) }
            }
        }
    }

    /// Legacy global search for callers that have no Space context (e.g. the Mac
    /// header search). Equivalent to `.allSpaces`.
    func search(_ query: String) -> [VaultItem] { search(query, scope: .allSpaces) }

    /// Whether widening a search to every Space is currently permitted. Always
    /// true today; a future isolated/anonymous identity will drive this false so
    /// its searches can never surface another identity's items.
    var allSpacesSearchAllowed: Bool { true }
}
