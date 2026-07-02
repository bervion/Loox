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
    /// WebAuthn flags this credential registered with. Nil means a legacy
    /// Vaultify passkey created before BE/BS support, so assertions keep UP|UV.
    var flags: UInt8?

    init(relyingParty: String, userName: String, userHandle: Data, credentialID: Data,
         privateKeyRaw: Data, counter: UInt32, createdAt: Date, flags: UInt8? = nil) {
        self.relyingParty = relyingParty
        self.userName = userName
        self.userHandle = userHandle
        self.credentialID = credentialID
        self.privateKeyRaw = privateKeyRaw
        self.counter = counter
        self.createdAt = createdAt
        self.flags = flags
    }
}

/// Non-secret passkey projection for app UI and identity publishing. Private
/// key material must stay out of repository/UI observable state.
nonisolated struct PasskeyInfo: Identifiable, Equatable, Sendable {
    var relyingParty: String
    var userName: String
    var userHandle: Data
    var credentialID: Data
    var createdAt: Date
    var lastUsedAt: Date?

    var id: String { recordIdentifier }
    var recordIdentifier: String { credentialID.base64URLEncodedString() }
}

/// Persistent record for one passkey. Content lives only in `sealed`
/// (AES-256-GCM under the Vault Key); `id` is the base64url credential id so
/// records stay unique and addressable without unsealing.
@Model
final class PasskeyRecord {
    @Attribute(.unique) var id: String
    var sealed: Data
    /// iOS 18 silent upgrades are written while the vault is locked. Those
    /// records live here until unlock-time migration re-seals them under
    /// `sealed`; old records keep this nil.
    var envelopeSealed: Data?
    /// Non-secret identity metadata used only to remove/quarantine envelope
    /// records that cannot be opened after a bundle mismatch.
    var relyingPartyHint: String?
    var userNameHint: String?
    var userHandleHint: Data?
    var createdAt: Date
    var usedAt: Date?

    init(id: String, sealed: Data, envelopeSealed: Data? = nil,
         relyingPartyHint: String? = nil, userNameHint: String? = nil,
         userHandleHint: Data? = nil, createdAt: Date = .now, usedAt: Date? = nil) {
        self.id = id
        self.sealed = sealed
        self.envelopeSealed = envelopeSealed
        self.relyingPartyHint = relyingPartyHint
        self.userNameHint = userNameHint
        self.userHandleHint = userHandleHint
        self.createdAt = createdAt
        self.usedAt = usedAt
    }
}

extension PasskeySecret {
    var info: PasskeyInfo {
        PasskeyInfo(relyingParty: relyingParty, userName: userName,
                    userHandle: userHandle, credentialID: credentialID,
                    createdAt: createdAt, lastUsedAt: nil)
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

    init?(base64URLEncodedString string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        if padding > 0 { base64.append(String(repeating: "=", count: padding)) }
        guard let data = Data(base64Encoded: base64) else { return nil }
        self = data
    }
}
