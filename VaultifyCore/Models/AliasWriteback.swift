import Foundation

/// Pure write-back helpers for private-email aliases (label constant +
/// idempotent field upsert). Lives in VaultifyCore so BOTH targets agree on
/// the field contract: the app writes the field, the AutoFill extension reads
/// it to offer the alias as an alternative username.
nonisolated enum AliasWriteback {
    /// Raw field label — localized at display via `fieldLabelText`; the catalog
    /// carries the VI value. Used as the stable key for idempotent upsert.
    static let privateEmailLabel = "Private email"

    /// Append the alias as a "Private email" field, or update it in place if one
    /// already exists — never duplicates, never disturbs the real Email field.
    static func upsertPrivateEmail(on item: VaultItem, address: String) -> VaultItem {
        var updated = item
        if let index = updated.fields.firstIndex(where: {
            $0.label == privateEmailLabel && $0.kind == .email
        }) {
            updated.fields[index].value = address
        } else {
            updated.fields.append(DynamicField(label: privateEmailLabel, kind: .email, value: address))
        }
        return updated
    }
}

extension VaultItem {
    /// The written-back private-email address on this item, if any — what the
    /// AutoFill extension offers as an alternative to the primary username.
    var privateEmailValue: String? {
        let value = fields.first {
            $0.label == AliasWriteback.privateEmailLabel && $0.kind == .email && !$0.isEmpty
        }?.value
        return value
    }
}
