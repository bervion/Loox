import Foundation

/// CSV import/export (1Password / Bitwarden / Chrome layouts) and a portable
/// passphrase-encrypted backup (Argon2id KEK → AES-256-GCM).
nonisolated enum VaultBackup {
    struct PortableItem: Codable {
        var title: String
        var category: String
        var fields: [DynamicField]
        var tags: [String]
        /// Folder by NAME (ids aren't portable across vaults); resolved on import.
        var folderName: String?
        /// Archived items travel in the backup (they are vault content) and
        /// restore back into the Archive instead of surfacing as live items.
        var archived: Bool
        /// Stable item id — a restore that keeps ids lets artifacts re-attach
        /// to their owner and makes re-importing the same backup idempotent.
        var id: String?
        var favorite: Bool?
        var pinned: Bool?
        /// The record-level icon override (`VaultItem.iconAsset`).
        var iconAssetOverride: String?
        var rotateDays: Int?
        var passwordChangedAt: Date?
        var createdAt: Date?
        var updatedAt: Date?

        init(title: String, category: String, fields: [DynamicField],
             tags: [String] = [], folderName: String? = nil, archived: Bool = false,
             id: String? = nil, favorite: Bool? = nil, pinned: Bool? = nil,
             iconAssetOverride: String? = nil, rotateDays: Int? = nil,
             passwordChangedAt: Date? = nil, createdAt: Date? = nil, updatedAt: Date? = nil) {
            self.title = title; self.category = category; self.fields = fields
            self.tags = tags; self.folderName = folderName; self.archived = archived
            self.id = id; self.favorite = favorite; self.pinned = pinned
            self.iconAssetOverride = iconAssetOverride; self.rotateDays = rotateDays
            self.passwordChangedAt = passwordChangedAt
            self.createdAt = createdAt; self.updatedAt = updatedAt
        }

        /// Back-compat decode: backups written before folders/tags/archive —
        /// and before the v2 identity/metadata fields — lack these keys.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            category = try c.decode(String.self, forKey: .category)
            fields = try c.decode([DynamicField].self, forKey: .fields)
            tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
            folderName = try c.decodeIfPresent(String.self, forKey: .folderName)
            archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
            id = try c.decodeIfPresent(String.self, forKey: .id)
            favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite)
            pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned)
            iconAssetOverride = try c.decodeIfPresent(String.self, forKey: .iconAssetOverride)
            rotateDays = try c.decodeIfPresent(Int.self, forKey: .rotateDays)
            passwordChangedAt = try c.decodeIfPresent(Date.self, forKey: .passwordChangedAt)
            createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        }
    }

    /// Envelope. Version 1 seals the payload directly under the passphrase KEK.
    /// Version 2 seals the payload under a random content key (CK) and stores
    /// the CK wrapped by the KEK in `wrappedCK` — so per-artifact keys inside
    /// the payload chain to one place and a future re-passphrase only re-wraps
    /// 32 bytes. `wrappedCK` is optional so v1 files still decode.
    struct EncryptedBackup: Codable {
        var version: Int
        var salt: Data
        var kdf: KdfParams
        var sealed: Data
        var wrappedCK: Data? = nil
    }

    /// One artifact on the backup wire: manifest fields in the clear WITHIN the
    /// sealed payload, the blob sealed again under its own random key, and that
    /// key wrapped by the backup content key (AAD-bound to id + owner).
    struct PortableArtifact: Codable {
        var id: String
        var ownerItemId: String
        var filename: String
        var utiType: String
        var byteCount: Int
        var plaintextSHA256: Data
        var wrappedKey: Data
        var blob: Data
    }

    /// Plaintext artifact exchanged with `ArtifactStore` on both sides of the
    /// wire: export input (decrypted from the vault) and validated import
    /// output (ready to re-seal under the destination vault key).
    struct ArtifactPayload {
        var id: String
        var ownerItemId: String
        var filename: String
        var utiType: String
        var data: Data
    }

    enum BackupFailure: Error, Equatable {
        /// A v2 envelope without its wrapped content key, or artifacts inside
        /// a payload that never carried one.
        case missingContentKey
        /// An artifact blob failed authentication, hash, or length validation.
        /// Import is all-or-nothing, so this aborts the whole restore.
        case artifactCorrupt
        /// An artifact whose id, owner id, or filename is not a value this app
        /// could ever have written. The id becomes `<id>.enc` inside the
        /// artifact root and the filename becomes a path component on export,
        /// so a crafted value is a file write of the author's choosing. The
        /// backup author picks the passphrase and hands it to the victim, so
        /// "needs the passphrase" is not a barrier here.
        case artifactUnsafePath
    }

    /// The Level-2 Secret Key wrap from the Keychain bundle. Sealed field values
    /// travel inside items, but without this wrap a restore on another device
    /// could never open them again — even with the correct Extra Password. The
    /// key stays wrapped (Argon2id from the Extra Password), so carrying it
    /// grants nothing the password didn't already.
    struct Level2Wrap: Codable {
        var wrappedL2SK: Data
        var salt: Data
        var kdf: KdfParams
    }

    struct EncryptedImport {
        var items: [(item: VaultItem, folderName: String?)]
        var passkeys: [PasskeySecret]
        var level2: Level2Wrap?
        /// Fully validated (authenticated + hash/length checked) artifact
        /// plaintexts. Populated only from v2 backups.
        var artifacts: [ArtifactPayload] = []
    }

    private struct PortableVaultPayload: Codable {
        var items: [PortableItem]
        var passkeys: [PasskeySecret]?
        var level2: Level2Wrap?
        var artifacts: [PortableArtifact]?
    }

    // MARK: CSV

    /// Back-compat thin wrapper — drops folder names (use `parseCSVWithFolders`
    /// when the caller can resolve folders against the repository).
    static func parseCSV(_ text: String) -> [VaultItem] {
        parseCSVWithFolders(text).map(\.item)
    }

    /// Parse a CSV into items plus an optional folder NAME per row. The caller
    /// resolves names to folder ids (match-or-create) against the live vault.
    static func parseCSVWithFolders(_ text: String) -> [(item: VaultItem, folderName: String?)] {
        let rows = parseRows(text)
        guard let header = rows.first else { return [] }
        let cols = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        func index(_ names: [String]) -> Int? { names.lazy.compactMap { cols.firstIndex(of: $0) }.first }
        let titleIdx = index(["name", "title", "account"])
        let userIdx = index(["username", "login_username", "user", "email"])
        let passIdx = index(["password", "login_password", "pass"])
        let urlIdx = index(["url", "login_uri", "website", "uri"])
        let noteIdx = index(["notes", "note"])
        let totpIdx = index(["otpauth", "totp", "one-time password"])
        let folderIdx = index(["folder", "collection", "space", "group", "grouping"])
        let tagsIdx = index(["tags", "tag"])

        var results: [(item: VaultItem, folderName: String?)] = []
        for row in rows.dropFirst() where row.contains(where: { !$0.isEmpty }) {
            func value(_ i: Int?) -> String { if let i, i < row.count { return row[i] } else { return "" } }
            let username = value(userIdx), password = value(passIdx)
            let url = value(urlIdx), notes = value(noteIdx), totp = value(totpIdx)
            var fields: [DynamicField] = []
            if !username.isEmpty { fields.append(DynamicField(label: "Username", kind: .username, value: username)) }
            if !password.isEmpty { fields.append(DynamicField(label: "Password", kind: .password, value: password, protected: true)) }
            if !totp.isEmpty { fields.append(DynamicField(label: "One-time Code", kind: .totp, value: totp, protected: true)) }
            if !url.isEmpty { fields.append(DynamicField(label: "Website", kind: .url, value: url)) }
            if !notes.isEmpty { fields.append(DynamicField(label: "Notes", kind: .multiline, value: notes)) }

            let rawTitle = value(titleIdx)
            let title = !rawTitle.isEmpty ? rawTitle : (url.isEmpty ? (username.isEmpty ? "Imported" : username) : url)
            let category: ItemCategory = (password.isEmpty && !notes.isEmpty && username.isEmpty) ? .note : .login
            let tags = value(tagsIdx).split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let folderRaw = value(folderIdx)
            results.append((VaultItem(category: category, title: title, fields: fields, tags: tags),
                            folderRaw.isEmpty ? nil : folderRaw))
        }
        return results
    }

    /// `folderNames` maps folder id → name so exported rows carry the folder name.
    static func makeCSV(_ items: [VaultItem], folderNames: [String: String] = [:]) -> String {
        var lines = ["name,username,password,url,notes,folder,tags"]
        for item in items {
            let folder = item.folderId.flatMap { folderNames[$0] } ?? ""
            // Extra-protected values are sealed ciphertext — exporting the raw
            // payload would be junk in every other password manager. A fixed
            // ASCII marker keeps the row while flagging the gap.
            func cell(_ field: DynamicField?) -> String {
                guard let field, !field.value.isEmpty else { return "" }
                return field.isExtraProtected ? "[protected]" : field.value
            }
            let cells = [item.title,
                         cell(item.usernameField),
                         cell(item.passwordField),
                         cell(item.urlField),
                         cell(item.firstField(of: .multiline)),
                         folder,
                         item.tags.joined(separator: "; ")]
            lines.append(cells.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Encrypted backup

    static func exportEncrypted(_ items: [VaultItem], folderNames: [String: String] = [:],
                                passkeys: [PasskeySecret] = [],
                                level2: Level2Wrap? = nil,
                                artifacts: [ArtifactPayload] = [],
                                passphrase: String) async throws -> Data {
        let portable = items.map {
            // An unknown-category item (written by a newer build) exports its
            // ORIGINAL raw category string — a backup round-trip through this
            // build must never permanently downgrade it to `custom`.
            PortableItem(title: $0.title,
                         category: $0.unknownCategoryRaw ?? $0.category.rawValue,
                         fields: $0.fields,
                         tags: $0.tags, folderName: $0.folderId.flatMap { folderNames[$0] },
                         archived: $0.archived,
                         id: $0.id, favorite: $0.favorite, pinned: $0.pinned,
                         iconAssetOverride: $0.iconAsset, rotateDays: $0.rotateDays,
                         passwordChangedAt: $0.passwordChangedAt,
                         createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
        var contentKey = CryptoRandom.bytes(32)
        defer { secureZero(&contentKey) }
        let contentKeyWrap = SecureBytes(contentKey)
        let portableArtifacts: [PortableArtifact] = try artifacts.map { payload in
            var blobKey = ArtifactCrypto.newDEK()
            defer { secureZero(&blobKey) }
            let blob = try ArtifactCrypto.sealArtifact(
                plaintext: payload.data, dek: blobKey,
                artifactID: payload.id, ownerItemID: payload.ownerItemId,
                purpose: ArtifactCrypto.purposeBackup)
            let wrappedKey = try ArtifactCrypto.wrapDEK(
                blobKey, under: contentKeyWrap,
                artifactID: payload.id, ownerItemID: payload.ownerItemId)
            return PortableArtifact(id: payload.id, ownerItemId: payload.ownerItemId,
                                    filename: payload.filename, utiType: payload.utiType,
                                    byteCount: payload.data.count,
                                    plaintextSHA256: ArtifactCrypto.sha256(payload.data),
                                    wrappedKey: wrappedKey, blob: blob)
        }
        let json = try JSONEncoder().encode(PortableVaultPayload(
            items: portable,
            passkeys: passkeys.isEmpty ? nil : passkeys,
            level2: level2,
            artifacts: portableArtifacts.isEmpty ? nil : portableArtifacts))
        let salt = KeyHierarchy.newSalt()
        let kdf = KdfParams.standard
        var kek = try await Task.detached(priority: .userInitiated) {
            try KeyHierarchy.deriveKEK(passphrase: passphrase, salt: salt, params: kdf)
        }.value
        defer { secureZero(&kek) }
        let sealed = try AESGCM.seal(json, key: contentKey)
        let wrappedCK = try AESGCM.seal(Data(contentKey), key: kek)
        return try JSONEncoder().encode(EncryptedBackup(version: 2, salt: Data(salt), kdf: kdf,
                                                        sealed: sealed, wrappedCK: wrappedCK))
    }

    static func importEncrypted(_ data: Data, passphrase: String) async throws -> [(item: VaultItem, folderName: String?)] {
        try await importEncryptedWithPasskeys(data, passphrase: passphrase).items
    }

    static func importEncryptedWithPasskeys(_ data: Data, passphrase: String) async throws -> EncryptedImport {
        let backup = try JSONDecoder().decode(EncryptedBackup.self, from: data)
        var kek = try await Task.detached(priority: .userInitiated) {
            try KeyHierarchy.deriveKEK(passphrase: passphrase, salt: Array(backup.salt), params: backup.kdf)
        }.value
        defer { secureZero(&kek) }
        // v1 seals the payload directly under the KEK; v2 goes through the CK.
        var contentKey: [UInt8] = []
        defer { secureZero(&contentKey) }
        let json: Data
        if backup.version >= 2 {
            guard let wrappedCK = backup.wrappedCK else { throw BackupFailure.missingContentKey }
            contentKey = Array(try AESGCM.open(wrappedCK, key: kek))
            json = try AESGCM.open(backup.sealed, key: contentKey)
        } else {
            json = try AESGCM.open(backup.sealed, key: kek)
        }
        let payload: PortableVaultPayload
        if let decoded = try? JSONDecoder().decode(PortableVaultPayload.self, from: json) {
            payload = decoded
        } else {
            payload = PortableVaultPayload(items: try JSONDecoder().decode([PortableItem].self, from: json),
                                           passkeys: nil, level2: nil)
        }
        let items = payload.items.map { portable -> (item: VaultItem, folderName: String?) in
            let known = ItemCategory(rawValue: portable.category)
            var item = VaultItem(id: portable.id ?? UUID().uuidString,
                                 category: known ?? .custom,
                                 title: portable.title, fields: portable.fields,
                                 favorite: portable.favorite ?? false,
                                 tags: portable.tags,
                                 iconAsset: portable.iconAssetOverride,
                                 pinned: portable.pinned ?? false,
                                 archived: portable.archived,
                                 rotateDays: portable.rotateDays ?? 0,
                                 passwordChangedAt: portable.passwordChangedAt,
                                 createdAt: portable.createdAt ?? .now,
                                 updatedAt: portable.updatedAt ?? .now)
            // Presentation degrades to `.custom`; identity is preserved so a
            // later save (or re-export) writes the original category back.
            item.unknownCategoryRaw = known == nil ? portable.category : nil
            return (item, portable.folderName)
        }
        let passkeys = try (payload.passkeys ?? []).map { secret in
            try PasskeyEnvelope.validate(secret)
            return secret
        }
        let artifacts = try validatedArtifacts(payload.artifacts, contentKey: contentKey)
        return EncryptedImport(items: items, passkeys: passkeys, level2: payload.level2,
                               artifacts: artifacts)
    }

    /// Authenticate + verify EVERY artifact blob before anything is returned:
    /// restore is all-or-nothing, so one corrupt blob fails the whole import
    /// here — before a single item or file could land.
    private static func validatedArtifacts(_ portables: [PortableArtifact]?,
                                           contentKey: [UInt8]) throws -> [ArtifactPayload] {
        guard let portables, !portables.isEmpty else { return [] }
        guard !contentKey.isEmpty else { throw BackupFailure.missingContentKey }
        let wrap = SecureBytes(contentKey)
        return try portables.map { portable in
            // Identity first, before a key is unwrapped and long before
            // anything is written: these three strings are the only values on
            // the wire that become filesystem paths downstream.
            guard isCanonicalUUID(portable.id),
                  isCanonicalUUID(portable.ownerItemId),
                  isBareFilename(portable.filename) else {
                throw BackupFailure.artifactUnsafePath
            }
            guard portable.byteCount <= ArtifactCrypto.maxPlaintextBytes else {
                throw BackupFailure.artifactCorrupt
            }
            let plaintext: Data
            do {
                var blobKey = try ArtifactCrypto.unwrapDEK(
                    portable.wrappedKey, under: wrap,
                    artifactID: portable.id, ownerItemID: portable.ownerItemId)
                defer { secureZero(&blobKey) }
                plaintext = try ArtifactCrypto.openArtifact(
                    envelope: portable.blob, dek: blobKey,
                    artifactID: portable.id, ownerItemID: portable.ownerItemId,
                    purpose: ArtifactCrypto.purposeBackup)
            } catch {
                throw BackupFailure.artifactCorrupt
            }
            guard plaintext.count == portable.byteCount,
                  ArtifactCrypto.sha256(plaintext) == portable.plaintextSHA256 else {
                throw BackupFailure.artifactCorrupt
            }
            return ArtifactPayload(id: portable.id, ownerItemId: portable.ownerItemId,
                                   filename: portable.filename, utiType: portable.utiType,
                                   data: plaintext)
        }
    }

    // MARK: Artifact identity policy

    /// `NAME_MAX` on APFS — one filesystem name can hold no more than this.
    private static let maxArtifactFilenameBytes = 255

    /// Ids this app could have written. Every artifact id and item id it
    /// creates is a `UUID().uuidString`, and the artifact id is turned into
    /// `<id>.enc` on disk, so a value that is not a canonical UUID is a path
    /// the store would never have produced.
    private static func isCanonicalUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    /// A bare basename: no path separator, no control character (NUL
    /// included), not a relative-directory token, and short enough for the
    /// filesystem. Backslash and colon are deliberately allowed — neither is a
    /// path separator on Darwin, and refusing them would reject legitimate
    /// attachment names. Empty is allowed too: `ArtifactStore.exportPlaintext`
    /// substitutes the artifact id for it.
    private static func isBareFilename(_ name: String) -> Bool {
        guard name.utf8.count <= maxArtifactFilenameBytes else { return false }
        guard name != ".", name != ".." else { return false }
        return !name.unicodeScalars.contains {
            $0 == "/" || CharacterSet.controlCharacters.contains($0)
        }
    }

    // MARK: CSV helpers

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r":
                    if c == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                    row.append(field); field = ""
                    rows.append(row); row = []
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
