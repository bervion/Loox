import Foundation

/// Second encryption layer on top of the VaultKey sealing. A protected field's
/// value is replaced by a tagged base64 `Payload` whose ciphertext is
/// decryptable only with the app-wide Level-2 Secret Key (L2SK) or a per-field
/// custom code — never from the unlocked vault alone. Forgetting the code makes
/// the field unrecoverable (by design).
nonisolated enum SecretGuard {
    static let tag = "v2g:" // marks a value as a protected payload

    enum Scheme: String, Codable, Sendable { case level2, custom }

    struct Payload: Codable, Sendable {
        var v: Int
        var scheme: Scheme
        var salt: Data?       // custom scheme only
        var kdf: KdfParams?   // custom scheme only
        var ct: Data          // AES-256-GCM(plaintext)
    }

    enum Failure: Error { case malformed, wrongCode }

    /// Whether a stored field value is a protected payload (and its scheme).
    static func scheme(of value: String) -> Scheme? { (try? decode(value))?.scheme }
    static func isProtected(_ value: String) -> Bool { value.hasPrefix(tag) }

    // MARK: Level-2 (app-wide L2SK held in memory after a Level-2 unlock)

    static func sealLevel2(_ plaintext: String, l2Key: [UInt8]) throws -> String {
        let ciphertext = try AESGCM.seal(Data(plaintext.utf8), key: l2Key)
        return try encode(Payload(v: 1, scheme: .level2, salt: nil, kdf: nil, ct: ciphertext))
    }

    static func openLevel2(_ value: String, l2Key: [UInt8]) throws -> String {
        let payload = try decode(value)
        guard payload.scheme == .level2 else { throw Failure.malformed }
        return String(decoding: try AESGCM.open(payload.ct, key: l2Key), as: UTF8.self)
    }

    // MARK: Custom code (Argon2id; heavy — runs off the main actor)

    static func sealCustom(_ plaintext: String, code: String, params: KdfParams = .standard) async throws -> String {
        let salt = KeyHierarchy.newSalt()
        var key = try await deriveCustom(code: code, salt: salt, params: params)
        defer { secureZero(&key) }
        let ciphertext = try AESGCM.seal(Data(plaintext.utf8), key: key)
        return try encode(Payload(v: 1, scheme: .custom, salt: Data(salt), kdf: params, ct: ciphertext))
    }

    static func openCustom(_ value: String, code: String) async throws -> String {
        let payload = try decode(value)
        guard payload.scheme == .custom, let salt = payload.salt, let kdf = payload.kdf else { throw Failure.malformed }
        var key = try await deriveCustom(code: code, salt: Array(salt), params: kdf)
        defer { secureZero(&key) }
        guard let data = try? AESGCM.open(payload.ct, key: key) else { throw Failure.wrongCode }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: helpers

    private static func deriveCustom(code: String, salt: [UInt8], params: KdfParams) async throws -> [UInt8] {
        try await Task.detached(priority: .userInitiated) {
            try Argon2.deriveRaw(password: code, salt: salt, params: params, length: 32)
        }.value
    }

    private static func encode(_ payload: Payload) throws -> String {
        tag + (try JSONEncoder().encode(payload)).base64EncodedString()
    }

    private static func decode(_ value: String) throws -> Payload {
        guard value.hasPrefix(tag), let data = Data(base64Encoded: String(value.dropFirst(tag.count))) else {
            throw Failure.malformed
        }
        return try JSONDecoder().decode(Payload.self, from: data)
    }
}
