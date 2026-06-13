import Foundation

/// Fully-decoded vault item held in memory while the vault is unlocked.
nonisolated struct VaultItem: Identifiable, Equatable, Sendable {
    var id: String
    var category: ItemCategory
    var title: String
    var folderId: String?
    var fields: [DynamicField]
    var favorite: Bool
    var createdAt: Date
    var updatedAt: Date
    var trashedAt: Date?

    init(id: String = UUID().uuidString,
         category: ItemCategory,
         title: String,
         folderId: String? = nil,
         fields: [DynamicField] = [],
         favorite: Bool = false,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         trashedAt: Date? = nil) {
        self.id = id
        self.category = category
        self.title = title
        self.folderId = folderId
        self.fields = fields
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.trashedAt = trashedAt
    }

    var isTrashed: Bool { trashedAt != nil }

    // MARK: Convenience field accessors

    func firstField(of kind: FieldKind) -> DynamicField? { fields.first { $0.kind == kind } }
    var usernameField: DynamicField? {
        fields.first { $0.kind == .username || $0.kind == .email }
    }
    var passwordField: DynamicField? { fields.first { $0.kind == .password } }
    var totpField: DynamicField? { fields.first { $0.kind == .totp && !$0.value.isEmpty } }
    var urlField: DynamicField? { fields.first { $0.kind == .url } }

    /// Subtitle shown in list rows (username/email/site, never the secret).
    var subtitle: String? {
        if let u = usernameField, !u.isEmpty { return u.value }
        if let s = urlField, !s.isEmpty { return s.value }
        return nil
    }

    /// Lowercased text used for in-memory search. Excludes protected values.
    var searchText: String {
        var parts = [title]
        for field in fields where !field.protected && !field.isEmpty { parts.append(field.value) }
        return parts.joined(separator: " ").lowercased()
    }

    /// The portion sealed (AES-256-GCM) at rest.
    var secret: ItemSecret {
        ItemSecret(title: title, category: category, folderId: folderId, fields: fields)
    }
}

/// The encrypted-at-rest payload of a vault item.
nonisolated struct ItemSecret: Codable, Sendable {
    var title: String
    var category: ItemCategory
    var folderId: String?
    var fields: [DynamicField]
}
