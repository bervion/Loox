import Foundation

/// Metadata for an attachment. Stored (small) inside the item's `.fileRef` field
/// value; the encrypted bytes live separately in the App Group container.
nonisolated struct AttachmentMeta: Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var ext: String
    var size: Int
    /// True when the bytes live in the v2 `ArtifactStore` (per-artifact DEK,
    /// backup-portable) instead of the legacy vault-key sidecar. Optional so
    /// every pre-existing pointer decodes unchanged, and old builds simply
    /// ignore the extra key.
    var v2: Bool? = nil

    static let tag = "att:"

    /// Encode into a `.fileRef` field value (the field is still sealed by the VaultKey).
    func encoded() -> String {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return Self.tag + data.base64EncodedString()
    }

    static func decode(_ value: String) -> AttachmentMeta? {
        guard value.hasPrefix(tag), let data = Data(base64Encoded: String(value.dropFirst(tag.count))) else { return nil }
        return try? JSONDecoder().decode(AttachmentMeta.self, from: data)
    }

    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }

    var iconAsset: String {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "webp": return Icons.image
        default: return Icons.attachment
        }
    }
}

/// Stores attachment bytes as individual AES-256-GCM blobs (sealed with the
/// Vault Key) in the shared App Group container. Requires an unlocked vault.
@MainActor final class AttachmentStore {
    private let session: VaultSession
    private let directory: URL

    init(session: VaultSession, directory: URL? = nil) {
        self.session = session
        self.directory = directory ?? SharedConfig.containerURL.appending(path: "Attachments")
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(for id: String) -> URL { directory.appending(path: "\(id).enc") }

    func save(_ data: Data, name: String, ext: String) throws -> AttachmentMeta {
        guard let key = session.vaultKey else { throw AuthError.locked }
        let id = UUID().uuidString
        let sealed = try AESGCM.seal(data, key: key)
        try sealed.write(to: url(for: id), options: [.atomic, .completeFileProtection])
        return AttachmentMeta(id: id, name: name, ext: ext, size: data.count)
    }

    func load(_ meta: AttachmentMeta) throws -> Data {
        guard let key = session.vaultKey else { throw AuthError.locked }
        let sealed = try Data(contentsOf: url(for: meta.id))
        return try AESGCM.open(sealed, key: key)
    }

    func delete(_ meta: AttachmentMeta) {
        try? FileManager.default.removeItem(at: url(for: meta.id))
    }

    /// Decrypt to a protected temp file for QuickLook / share. Caller should
    /// delete the returned URL when finished.
    func decryptToTemp(_ meta: AttachmentMeta) throws -> URL {
        let data = try load(meta)
        let fileName = meta.name.isEmpty ? "\(meta.id).\(meta.ext)" : meta.name
        let temp = FileManager.default.temporaryDirectory.appending(path: fileName)
        try data.write(to: temp, options: [.completeFileProtection])
        return temp
    }
}
