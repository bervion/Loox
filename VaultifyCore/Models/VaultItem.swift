import Foundation

/// Fully-decoded vault item held in memory while the vault is unlocked.
nonisolated struct VaultItem: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var category: ItemCategory
    var title: String
    var folderId: String?
    var fields: [DynamicField]
    var favorite: Bool
    var tags: [String]
    /// Optional icon override (a Polaris icon asset name). `nil` → the UI shows the default
    /// letter-avatar (initials + colour derived from the title). Sealed at rest.
    var iconAsset: String?
    /// Last in-app copy/reveal time. Powers Recents; plaintext metadata mirrored
    /// from `ItemRecord.lastUsedAt` so Home can sort without re-decrypting.
    var lastUsedAt: Date?
    var pinned: Bool
    var archived: Bool
    var useCount: Int
    /// Marks this as the user's default identity (only meaningful for `.identity`).
    /// Mirrored from `ItemRecord.isDefaultIdentity`; set via the repository's
    /// default-identity API (not by the editor), so the editor's `update` preserves it.
    var isDefaultIdentity: Bool
    /// Rotation reminder cadence in days: 0 = off, 15 / 30 / 90 = enabled.
    /// Mirrored from `ItemRecord.rotateDays` so the editor and Home can read
    /// cadence without re-decrypting.
    var rotateDays: Int
    /// When the password was last changed. Nil → `createdAt` used as baseline
    /// in `RotationStatus`. Mirrored from `ItemRecord.passwordChangedAt`.
    var passwordChangedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var trashedAt: Date?

    init(id: String = UUID().uuidString,
         category: ItemCategory,
         title: String,
         folderId: String? = nil,
         fields: [DynamicField] = [],
         favorite: Bool = false,
         tags: [String] = [],
         iconAsset: String? = nil,
         lastUsedAt: Date? = nil,
         pinned: Bool = false,
         archived: Bool = false,
         useCount: Int = 0,
         isDefaultIdentity: Bool = false,
         rotateDays: Int = 0,
         passwordChangedAt: Date? = nil,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         trashedAt: Date? = nil) {
        self.id = id
        self.category = category
        self.title = title
        self.folderId = folderId
        self.fields = fields
        self.favorite = favorite
        self.tags = tags
        self.iconAsset = iconAsset
        self.lastUsedAt = lastUsedAt
        self.pinned = pinned
        self.archived = archived
        self.useCount = useCount
        self.isDefaultIdentity = isDefaultIdentity
        self.rotateDays = rotateDays
        self.passwordChangedAt = passwordChangedAt
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

    /// Lowercased text used for in-memory search. Excludes protected values;
    /// includes tags so `#work` etc. are searchable.
    var searchText: String {
        var parts = [title]
        for field in fields where !field.protected && !field.isEmpty { parts.append(field.value) }
        parts.append(contentsOf: tags)
        return parts.joined(separator: " ").lowercased()
    }

    /// The portion sealed (AES-256-GCM) at rest.
    var secret: ItemSecret {
        ItemSecret(title: title, category: category, folderId: folderId,
                   fields: fields, tags: tags, iconAsset: iconAsset)
    }
}

/// The encrypted-at-rest payload of a vault item.
nonisolated struct ItemSecret: Codable, Sendable {
    var title: String
    var category: ItemCategory
    var folderId: String?
    var fields: [DynamicField]
    var tags: [String]
    var iconAsset: String?

    init(title: String,
         category: ItemCategory,
         folderId: String? = nil,
         fields: [DynamicField],
         tags: [String] = [],
         iconAsset: String? = nil) {
        self.title = title
        self.category = category
        self.folderId = folderId
        self.fields = fields
        self.tags = tags
        self.iconAsset = iconAsset
    }

    /// Custom decode so legacy sealed blobs (written before `tags` existed) still
    /// open: a missing `tags` key yields `[]` instead of failing the decode —
    /// without this, every pre-existing item would look corrupt. `encode(to:)`
    /// and `CodingKeys` stay compiler-synthesized.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        category = try c.decode(ItemCategory.self, forKey: .category)
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        fields = try c.decode([DynamicField].self, forKey: .fields)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        iconAsset = try c.decodeIfPresent(String.self, forKey: .iconAsset)
    }
}
