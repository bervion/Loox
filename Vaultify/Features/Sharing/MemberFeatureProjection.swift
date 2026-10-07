import Foundation

/// One ownership rule for Member counters, records, and item choosers.
/// Missing non-nil folder IDs are unknown ownership, never Personal.
nonisolated enum MemberFeatureProjection {
    static func ownedItems(items: [VaultItem], folders: [Folder], persona: Persona?,
                           defaultPersonaID: String?) -> [VaultItem] {
        guard let persona else { return [] }
        let folderIDs = Set(folders.filter {
            ($0.personaId ?? defaultPersonaID) == persona.id
        }.map(\.id))
        return items.filter { item in
            if let folderID = item.folderId { return folderIDs.contains(folderID) }
            return persona.isDefault
        }
    }

    static func eligibleItems(_ ownedItems: [VaultItem], needsSnapshotFields: Bool) -> [VaultItem] {
        ownedItems.filter {
            !$0.isTrashed && !$0.archived && !$0.isUnsupportedSchema && $0.sharedOrigin == nil
                && (!needsSnapshotFields || !LooxLinkEnvelope.shareableFields(of: $0).isEmpty)
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func links(_ records: [LooxLinkRecord], ownedItems: [VaultItem], now: Date = .now) -> [LooxLinkRecord] {
        let IDs = Set(ownedItems.map(\.id))
        return records.filter { IDs.contains($0.itemId) && $0.expiresAt > now }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func browserAttempts(_ rows: [QuickViewHistoryRow], ownedItems: [VaultItem]) -> [QuickViewHistoryRow] {
        let IDs = Set(ownedItems.map(\.id))
        return rows.filter { IDs.contains($0.itemID) }.sorted { $0.timestamp > $1.timestamp }
    }

    static func outgoingShares(_ records: [ItemShareRecord], ownedItems: [VaultItem]) -> [ItemShareRecord] {
        let IDs = Set(ownedItems.map(\.id))
        return records.filter { IDs.contains($0.itemId) }
    }
}

extension VaultRepository {
    /// Unlike the legacy all-items fallback, a Member surface requires a
    /// known active persona before it can disclose records or offer actions.
    var memberOwnedItems: [VaultItem] {
        MemberFeatureProjection.ownedItems(items: items, folders: folders,
                                          persona: activePersona, defaultPersonaID: defaultPersona?.id)
    }

    func memberCanUseItem(_ itemID: String, personaID: String?, needsSnapshotFields: Bool) -> Bool {
        guard activePersona?.id == personaID, personaID != nil else { return false }
        return MemberFeatureProjection.eligibleItems(memberOwnedItems, needsSnapshotFields: needsSnapshotFields)
            .contains { $0.id == itemID }
    }
}
