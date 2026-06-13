import Foundation
import SwiftData

/// Read/write access to stored passkeys in the shared vault store. Used by the
/// AutoFill extension during passkey registration (write) and assertion (read),
/// after the master password has unwrapped the Vault Key.
@MainActor
enum PasskeyVault {

    /// Seal and persist a freshly registered passkey.
    static func save(_ secret: PasskeySecret, key: [UInt8]) throws {
        let sealed = try AESGCM.seal(JSONEncoder().encode(secret), key: key)
        let store = VaultStore()
        store.context.insert(PasskeyRecord(id: secret.credentialID.base64URLEncodedString(),
                                           sealed: sealed, createdAt: secret.createdAt))
        try store.context.save()
    }

    /// All stored passkeys, decrypted with the Vault Key.
    static func all(key: [UInt8]) -> [PasskeySecret] {
        let store = VaultStore()
        let records = (try? store.context.fetch(FetchDescriptor<PasskeyRecord>())) ?? []
        return records.compactMap { record in
            guard let plaintext = try? AESGCM.open(record.sealed, key: key) else { return nil }
            return try? JSONDecoder().decode(PasskeySecret.self, from: plaintext)
        }
    }

    /// Passkeys for a relying party, optionally narrowed to specific credential ids.
    static func matching(relyingParty: String, allowedCredentialIDs: [Data], key: [UInt8]) -> [PasskeySecret] {
        all(key: key).filter { secret in
            guard secret.relyingParty == relyingParty else { return false }
            return allowedCredentialIDs.isEmpty || allowedCredentialIDs.contains(secret.credentialID)
        }
    }
}
