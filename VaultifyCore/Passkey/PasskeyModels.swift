import Foundation
import SwiftData

/// The encrypted-at-rest payload of a stored passkey. Holds the P-256 private
/// key (raw, 32 bytes) plus the WebAuthn relying party / user binding. Sealed
/// under the Vault Key exactly like a vault item.
nonisolated struct PasskeySecret: Codable, Sendable {
    var relyingParty: String
    var userName: String
    var userHandle: Data
    var credentialID: Data
    var privateKeyRaw: Data
    var counter: UInt32
    var createdAt: Date
}

/// Persistent record for one passkey. Content lives only in `sealed`
/// (AES-256-GCM under the Vault Key); `id` is the base64url credential id so
/// records stay unique and addressable without unsealing.
@Model
final class PasskeyRecord {
    @Attribute(.unique) var id: String
    var sealed: Data
    var createdAt: Date

    init(id: String, sealed: Data, createdAt: Date = .now) {
        self.id = id
        self.sealed = sealed
        self.createdAt = createdAt
    }
}

extension Data {
    /// base64url (no padding) — used for credential ids and WebAuthn fields.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
