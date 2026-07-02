import Foundation
import os
import SwiftData

private let passkeyVaultLog = Logger(subsystem: "com.bervion.vaultify", category: "passkey-vault")

/// Read/write access to stored passkeys in the shared vault store. Callers
/// inject the store they already own; passkey code never spins up an implicit
/// SwiftData container mid-ceremony.
@MainActor
struct PasskeyVault {
    struct SaveResult { let replaced: [PasskeySecret] }

    let store: VaultStore

    init(store: VaultStore) {
        self.store = store
    }

    /// Seal and persist a passkey, replacing any prior credential for the same
    /// RP + userHandle in a single save.
    func save(_ secret: PasskeySecret, key: [UInt8]) throws -> SaveResult {
        let sealed = try seal(secret, key: key)
        let replaced = secretsForReplacement(secret, key: key)
        for entry in replaced { deletePending(credentialID: entry.credentialID) }
        store.context.insert(PasskeyRecord(id: secret.credentialID.base64URLEncodedString(),
                                           sealed: sealed, createdAt: secret.createdAt))
        try store.context.save()
        return SaveResult(replaced: replaced)
    }

    func save(_ secret: PasskeySecret, key: SecureBytes) throws -> SaveResult {
        try key.withUnsafeBytes { try save(secret, key: Array($0)) }
    }

    /// All stored passkey metadata, decrypted with the Vault Key.
    func all(key: [UInt8]) -> [PasskeyInfo] {
        allDecoded(key: key)
            .map { info(secret: $0.secret, record: $0.record) }
            .sorted(by: passkeySort)
    }

    func all(key: SecureBytes) -> [PasskeyInfo] {
        key.withUnsafeBytes { all(key: Array($0)) }
    }

    /// Passkey metadata for a relying party, optionally narrowed to credential ids.
    func matching(relyingParty: String, allowedCredentialIDs: [Data], key: [UInt8]) -> [PasskeyInfo] {
        all(key: key).filter { info in
            guard info.relyingParty == relyingParty else { return false }
            return allowedCredentialIDs.isEmpty || allowedCredentialIDs.contains(info.credentialID)
        }
    }

    func matching(relyingParty: String, allowedCredentialIDs: [Data], key: SecureBytes) -> [PasskeyInfo] {
        key.withUnsafeBytes { matching(relyingParty: relyingParty, allowedCredentialIDs: allowedCredentialIDs, key: Array($0)) }
    }

    /// Private key access for the signing path only.
    func secret(credentialID: Data, key: [UInt8]) -> PasskeySecret? {
        guard let record = record(credentialID: credentialID),
              let plaintext = try? AESGCM.open(record.sealed, key: key)
        else { return nil }
        return try? JSONDecoder().decode(PasskeySecret.self, from: plaintext)
    }

    func secret(credentialID: Data, key: SecureBytes) -> PasskeySecret? {
        key.withUnsafeBytes { secret(credentialID: credentialID, key: Array($0)) }
    }

    func delete(credentialID: Data) throws {
        guard let record = record(credentialID: credentialID) else { return }
        store.context.delete(record)
        try store.context.save()
    }

    func hasRecord(credentialID: Data) -> Bool {
        record(credentialID: credentialID) != nil
    }

    /// Non-fatal metadata touch after successful assertion.
    func touchLastUsed(credentialID: Data) {
        guard let record = record(credentialID: credentialID) else { return }
        record.usedAt = .now
        do {
            try store.context.save()
        } catch {
            passkeyVaultLog.error("touch-last-used-failed")
        }
    }

    private func seal(_ secret: PasskeySecret, key: [UInt8]) throws -> Data {
        try AESGCM.seal(JSONEncoder().encode(secret), key: key)
    }

    private func records() -> [PasskeyRecord] {
        (try? store.context.fetch(FetchDescriptor<PasskeyRecord>())) ?? []
    }

    private func allDecoded(key: [UInt8]) -> [(record: PasskeyRecord, secret: PasskeySecret)] {
        records().compactMap { record in
            guard let plaintext = try? AESGCM.open(record.sealed, key: key),
                  let secret = try? JSONDecoder().decode(PasskeySecret.self, from: plaintext)
            else { return nil }
            return (record, secret)
        }
    }

    private func secretsForReplacement(_ secret: PasskeySecret, key: [UInt8]) -> [PasskeySecret] {
        let newID = secret.credentialID.base64URLEncodedString()
        return allDecoded(key: key).compactMap { record, existing in
            let sameAccount = existing.relyingParty == secret.relyingParty && existing.userHandle == secret.userHandle
            return (sameAccount || record.id == newID) ? existing : nil
        }
    }

    private func record(credentialID: Data) -> PasskeyRecord? {
        let id = credentialID.base64URLEncodedString()
        var descriptor = FetchDescriptor<PasskeyRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? store.context.fetch(descriptor).first
    }

    private func deletePending(credentialID: Data) {
        if let record = record(credentialID: credentialID) {
            store.context.delete(record)
        }
    }

    private func info(secret: PasskeySecret, record: PasskeyRecord) -> PasskeyInfo {
        PasskeyInfo(relyingParty: secret.relyingParty,
                    userName: secret.userName,
                    userHandle: secret.userHandle,
                    credentialID: secret.credentialID,
                    createdAt: secret.createdAt,
                    lastUsedAt: record.usedAt)
    }

    private func passkeySort(_ lhs: PasskeyInfo, _ rhs: PasskeyInfo) -> Bool {
        let leftUsed = lhs.lastUsedAt ?? .distantPast
        let rightUsed = rhs.lastUsedAt ?? .distantPast
        if leftUsed != rightUsed { return leftUsed > rightUsed }
        return lhs.createdAt > rhs.createdAt
    }
}
