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
    /// Non-nil ONLY on recipient-side projections built from a share grant
    /// (`SharedItemsProjection`) — such items are read-only, never enter the
    /// vault store, and therefore never sync, export, back up, or AutoFill.
    /// Excluded from `secret`, so it can never be sealed at rest either.
    var sharedOrigin: SharedOrigin? = nil
    /// Mirrors `ItemSecret.unknownCategoryRaw`: non-nil when this item was
    /// written by a newer build with a category this build does not know.
    /// `category` is then the generic `.custom` presentation fallback; saving
    /// the item re-seals the ORIGINAL raw value, never the fallback.
    var unknownCategoryRaw: String? = nil
    /// Semantic identity (stable kind ID, template provenance, typed links).
    /// Mirrors `ItemSecret.semantics`; nil on legacy items.
    var semantics: ItemSemantics? = nil

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
    /// `usernameField` for display/export surfaces: an extra-protected value is
    /// sealed ciphertext, so surfacing it would print `v2g:…` noise — skip to
    /// the first readable candidate instead.
    var readableUsernameField: DynamicField? {
        fields.first { ($0.kind == .username || $0.kind == .email) && !$0.isExtraProtected }
    }
    var passwordField: DynamicField? { fields.first { $0.kind == .password } }
    /// The USABLE TOTP field — an extra-protected seed is sealed ciphertext, so
    /// it can't drive live codes, QuickType OTP identities, or 2FA listings.
    var totpField: DynamicField? { fields.first { $0.kind == .totp && !$0.value.isEmpty && !$0.isExtraProtected } }
    var urlField: DynamicField? { fields.first { $0.kind == .url } }

    /// Subtitle shown in list rows (username/email/site, never the secret —
    /// an extra-protected value is ciphertext and must not surface either).
    var subtitle: String? {
        if let u = usernameField, !u.isEmpty, !u.isExtraProtected { return u.value }
        if let s = urlField, !s.isEmpty, !s.isExtraProtected { return s.value }
        return nil
    }

    /// Lowercased text used for in-memory search. Excludes protected and
    /// extra-protected values; includes tags so `#work` etc. are searchable.
    var searchText: String {
        var parts = [title]
        for field in fields where !field.protected && !field.isEmpty && !field.isExtraProtected {
            parts.append(field.value)
        }
        parts.append(contentsOf: tags)
        return parts.joined(separator: " ").lowercased()
    }

    /// The portion sealed (AES-256-GCM) at rest.
    var secret: ItemSecret {
        ItemSecret(title: title, category: category, folderId: folderId,
                   fields: fields, tags: tags, iconAsset: iconAsset,
                   unknownCategoryRaw: unknownCategoryRaw,
                   semantics: semantics)
    }

    /// True when this item was written by a build with a NEWER incompatible
    /// wire generation: it must stay concealed read-only (recovery only) and
    /// its original ciphertext must never be typed re-encoded.
    var isUnsupportedSchema: Bool {
        semantics.map { !$0.isSupportedSchema } ?? false
    }

    /// The stable behavioral identity, when present.
    var kindID: ItemKindID? { semantics?.kindID }
    /// Typed links to related items (auth key, API secret, recovery item…).
    var links: [ItemLink] { semantics?.links ?? [] }
}

/// The encrypted-at-rest payload of a vault item.
nonisolated struct ItemSecret: Codable, Sendable {
    var title: String
    var category: ItemCategory
    var folderId: String?
    var fields: [DynamicField]
    var tags: [String]
    var iconAsset: String?
    /// The original `category` raw value when it names a category this build
    /// does not know (an item written by a NEWER app). The item presents as a
    /// generic `.custom` item, but re-encoding writes this raw value back —
    /// cross-version data is degraded in presentation, never rewritten.
    var unknownCategoryRaw: String?
    /// Optional semantic identity (stable kind ID, template provenance, typed
    /// links). Absent on legacy items; `category` remains the coarse
    /// presentation fallback while this is the behavioral identity.
    var semantics: ItemSemantics?

    init(title: String,
         category: ItemCategory,
         folderId: String? = nil,
         fields: [DynamicField],
         tags: [String] = [],
         iconAsset: String? = nil,
         unknownCategoryRaw: String? = nil,
         semantics: ItemSemantics? = nil) {
        self.title = title
        self.category = category
        self.folderId = folderId
        self.fields = fields
        self.tags = tags
        self.iconAsset = iconAsset
        self.unknownCategoryRaw = unknownCategoryRaw
        self.semantics = semantics
    }

    private enum CodingKeys: String, CodingKey {
        case title, category, folderId, fields, tags, iconAsset, semantics
    }

    /// Custom decode so legacy sealed blobs (written before `tags` existed) still
    /// open: a missing `tags` key yields `[]` instead of failing the decode —
    /// without this, every pre-existing item would look corrupt. A category raw
    /// value this build does not know presents as `.custom` while the original
    /// string is preserved for lossless re-encode (never silently dropped, never
    /// rewritten to a different category).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        let rawCategory = try c.decode(String.self, forKey: .category)
        if let known = ItemCategory(rawValue: rawCategory) {
            category = known
            unknownCategoryRaw = nil
        } else {
            category = .custom
            unknownCategoryRaw = rawCategory
        }
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId)
        fields = try c.decode([DynamicField].self, forKey: .fields)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        iconAsset = try c.decodeIfPresent(String.self, forKey: .iconAsset)
        semantics = try c.decodeIfPresent(ItemSemantics.self, forKey: .semantics)
    }

    /// Custom encode: an unknown-category item re-seals with its ORIGINAL raw
    /// category string, so a round-trip through an older build is lossless.
    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(unknownCategoryRaw ?? category.rawValue, forKey: .category)
        try c.encodeIfPresent(folderId, forKey: .folderId)
        try c.encode(fields, forKey: .fields)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(iconAsset, forKey: .iconAsset)
        try c.encodeIfPresent(semantics, forKey: .semantics)
    }
}
