import Foundation

/// Canonical field contract shared with AutoFill. Ordinary Email/username values
/// are never edited by alias relation management.
nonisolated enum AliasWriteback {
    static let privateEmailLabel = "Private email"

    enum Failure: Error, Equatable {
        case protectedField
        case duplicateFields
        case conflictingAddress
        case staleField
    }

    static func canonicalFields(on item: VaultItem) -> [DynamicField] {
        item.fields.filter { $0.label == privateEmailLabel && $0.kind == .email }
    }

    /// A field with additional protection cannot be read or overwritten here.
    /// The item editor's action-bound protection gate owns repair/removal.
    static func readableField(on item: VaultItem) throws -> DynamicField? {
        let fields = canonicalFields(on: item)
        guard fields.count <= 1 else { throw Failure.duplicateFields }
        guard let field = fields.first else { return nil }
        guard !field.isExtraProtected, !field.protected,
              field.semantics?.cryptoProtection != .level2Key,
              (field.semantics?.actionAuthorization ?? ActionAuthorization.none) == ActionAuthorization.none else { throw Failure.protectedField }
        return field
    }

    /// Idempotent linking, fail closed when another private address is present.
    static func linking(_ item: VaultItem, address: String) throws -> VaultItem {
        var updated = item
        if let field = try readableField(on: item) {
            guard field.value.isEmpty || field.value == address else { throw Failure.conflictingAddress }
            if let index = updated.fields.firstIndex(where: { $0.id == field.id }) {
                updated.fields[index].value = address
            }
        } else {
            updated.fields.append(DynamicField(label: privateEmailLabel, kind: .email, value: address))
        }
        return updated
    }

    /// Exact field removal. Never infer that an ordinary username is a relation.
    static func unlinking(_ item: VaultItem, fieldID: String, address: String) throws -> VaultItem {
        guard let field = try readableField(on: item), field.id == fieldID,
              field.value == address else { throw Failure.staleField }
        var updated = item
        updated.fields.removeAll { $0.id == fieldID }
        return updated
    }

    /// Legacy profile writeback supports replacement, but protection/duplicates
    /// remain fail closed. Login relation writers use `linking` instead.
    static func upsertPrivateEmail(on item: VaultItem, address: String) -> VaultItem {
        guard let field = try? readableField(on: item) else {
            return (try? linking(item, address: address)) ?? item
        }
        if item.category == .login, !field.isEmpty, field.value != address { return item }
        var updated = item
        if let index = updated.fields.firstIndex(where: { $0.id == field.id }) {
            updated.fields[index].value = address
        }
        return updated
    }
}

extension VaultItem {
    var privateEmailValue: String? {
        guard let field = try? AliasWriteback.readableField(on: self), !field.isEmpty else { return nil }
        return field.value
    }
}
