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

        init(title: String, category: String, fields: [DynamicField],
             tags: [String] = [], folderName: String? = nil) {
            self.title = title; self.category = category; self.fields = fields
            self.tags = tags; self.folderName = folderName
        }

        /// Back-compat decode: backups written before folders/tags lack these keys.
        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            category = try c.decode(String.self, forKey: .category)
            fields = try c.decode([DynamicField].self, forKey: .fields)
            tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
            folderName = try c.decodeIfPresent(String.self, forKey: .folderName)
        }
    }
    struct EncryptedBackup: Codable { var version: Int; var salt: Data; var kdf: KdfParams; var sealed: Data }
    struct EncryptedImport {
        var items: [(item: VaultItem, folderName: String?)]
        var passkeys: [PasskeySecret]
    }

    private struct PortableVaultPayload: Codable {
        var items: [PortableItem]
        var passkeys: [PasskeySecret]?
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
            let cells = [item.title,
                         item.usernameField?.value ?? "",
                         item.passwordField?.value ?? "",
                         item.urlField?.value ?? "",
                         item.firstField(of: .multiline)?.value ?? "",
                         folder,
                         item.tags.joined(separator: "; ")]
            lines.append(cells.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Encrypted backup

    static func exportEncrypted(_ items: [VaultItem], folderNames: [String: String] = [:],
                                passkeys: [PasskeySecret] = [],
                                passphrase: String) async throws -> Data {
        let portable = items.map {
            PortableItem(title: $0.title, category: $0.category.rawValue, fields: $0.fields,
                         tags: $0.tags, folderName: $0.folderId.flatMap { folderNames[$0] })
        }
        let json = try JSONEncoder().encode(PortableVaultPayload(items: portable,
                                                                 passkeys: passkeys.isEmpty ? nil : passkeys))
        let salt = KeyHierarchy.newSalt()
        let kdf = KdfParams.standard
        var kek = try await Task.detached(priority: .userInitiated) {
            try KeyHierarchy.deriveKEK(passphrase: passphrase, salt: salt, params: kdf)
        }.value
        defer { secureZero(&kek) }
        let sealed = try AESGCM.seal(json, key: kek)
        return try JSONEncoder().encode(EncryptedBackup(version: 1, salt: Data(salt), kdf: kdf, sealed: sealed))
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
        let json = try AESGCM.open(backup.sealed, key: kek)
        let payload: PortableVaultPayload
        if let decoded = try? JSONDecoder().decode(PortableVaultPayload.self, from: json) {
            payload = decoded
        } else {
            payload = PortableVaultPayload(items: try JSONDecoder().decode([PortableItem].self, from: json),
                                           passkeys: nil)
        }
        let items = payload.items.map {
            (VaultItem(category: ItemCategory(rawValue: $0.category) ?? .custom,
                       title: $0.title, fields: $0.fields, tags: $0.tags), $0.folderName)
        }
        let passkeys = try (payload.passkeys ?? []).map { secret in
            try PasskeyEnvelope.validate(secret)
            return secret
        }
        return EncryptedImport(items: items, passkeys: passkeys)
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
