import Foundation

/// An ephemeral projection of an owned Login's sealed canonical field. No extra
/// association array is persisted: the field itself is the source of truth.
nonisolated struct AliasLinkedService: Identifiable, Equatable, Sendable {
    var id: String { itemID + ":" + aliasID }
    let itemID: String
    let aliasID: String
    let personaID: String
    let fieldID: String
    let itemTitle: String
    let website: String?
    let address: String
    let itemUpdatedAt: Date
    let aliasRelationRevision: UInt64
    let isLegacyCandidate: Bool
}

nonisolated enum AliasLinkedServices {
    /// Callers supply only canonical-owned persona items; missing-folder items
    /// must not be guessed into the default persona by a convenience resolver.
    static func project(items: [VaultItem], aliases: [EmailAlias], personaID: String,
                        aliasID: String? = nil, legacyReview: Bool = false) -> [AliasLinkedService] {
        let owned = aliases.filter { $0.personaId == personaID && (aliasID == nil || $0.id == aliasID) }
        var result: [AliasLinkedService] = []
        for item in items where item.category == .login && item.sharedOrigin == nil
            && !item.isUnsupportedSchema && !item.isTrashed && !item.archived {
            let fields = AliasWriteback.canonicalFields(on: item)
            guard fields.count <= 1, (try? AliasWriteback.readableField(on: item)) != nil || fields.isEmpty else { continue }
            let canonical = fields.first
            for alias in owned {
                guard let address = alias.resolvedAddress else { continue }
                let field: DynamicField?
                if legacyReview {
                    // Explicit, read-only candidate scan; no auto-adoption/count.
                    guard canonical == nil || canonical?.isEmpty == true else { continue }
                    field = item.fields.first { ($0.kind == .email || $0.kind == .username)
                        && $0.label != AliasWriteback.privateEmailLabel && !$0.protected
                        && !$0.isExtraProtected && $0.semantics?.cryptoProtection != .level2Key
                        && ($0.semantics?.actionAuthorization ?? ActionAuthorization.none) == ActionAuthorization.none && $0.value == address }
                } else {
                    field = canonical?.value == address ? canonical : nil
                }
                guard let field else { continue }
                result.append(AliasLinkedService(itemID: item.id, aliasID: alias.id,
                    personaID: personaID, fieldID: field.id, itemTitle: item.title,
                    website: item.autofillHost, address: address, itemUpdatedAt: item.updatedAt,
                    aliasRelationRevision: alias.relationRevision, isLegacyCandidate: legacyReview))
            }
        }
        return result.sorted { ($0.itemTitle.localizedLowercase, $0.itemID) < ($1.itemTitle.localizedLowercase, $1.itemID) }
    }
}
