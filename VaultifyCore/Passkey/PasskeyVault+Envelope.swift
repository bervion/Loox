import Foundation
import os
import SwiftData

private let passkeyEnvelopeLog = Logger(subsystem: "com.bervion.vaultify", category: "passkey-envelope")

extension PasskeyVault {
    struct EnvelopeMigrationResult {
        var migrated: Int = 0
        var replaced: [PasskeySecret] = []
        var quarantinedSites: [String] = []
        var quarantinedIdentities: [PasskeyInfo] = []
    }

    /// Store a locked-write passkey envelope. No dedupe here: random credential ids
    /// make replacement impossible without opening; unlock migration reconciles.
    func saveEnvelope(_ secret: PasskeySecret, envelopeSealed: Data) throws {
        let id = secret.credentialID.base64URLEncodedString()
        if let existing = record(id: id) {
            existing.sealed = Data()
            existing.envelopeSealed = envelopeSealed
            existing.relyingPartyHint = secret.relyingParty
            existing.userNameHint = secret.userName
            existing.userHandleHint = secret.userHandle
            existing.createdAt = secret.createdAt
            existing.usedAt = nil
        } else {
            store.context.insert(PasskeyRecord(id: id, sealed: Data(), envelopeSealed: envelopeSealed,
                                               relyingPartyHint: secret.relyingParty,
                                               userNameHint: secret.userName,
                                               userHandleHint: secret.userHandle,
                                               createdAt: secret.createdAt))
        }
        try store.context.save()
    }

    /// Verify/provision the envelope key and promote locked-write records into
    /// normal Vault-Key sealed passkeys. Reads never call this.
    func prepareEnvelopeOnUnlock(key: [UInt8]) -> EnvelopeMigrationResult {
        var result = EnvelopeMigrationResult()
        do {
            let state = try PasskeyEnvelope.provisionOrVerify(vaultKey: key)
            if state == .mismatch {
                return quarantineEnvelopeRecords()
            }
            result = migrateEnvelopeRecords(key: key)
        } catch PasskeyEnvelope.Failure.noVault {
            return result
        } catch {
            passkeyEnvelopeLog.error("envelope-prepare-failed")
        }
        return result
    }

    func prepareEnvelopeOnUnlock(key: SecureBytes) -> EnvelopeMigrationResult {
        key.withUnsafeBytes { prepareEnvelopeOnUnlock(key: Array($0)) }
    }

    private func migrateEnvelopeRecords(key: [UInt8]) -> EnvelopeMigrationResult {
        var result = EnvelopeMigrationResult()
        var didDelete = false
        let envelopeRecords = records()
            .filter { $0.envelopeSealed != nil }
            .sorted { $0.createdAt < $1.createdAt }
        for record in envelopeRecords {
            guard let envelope = record.envelopeSealed else { continue }
            do {
                let secret = try PasskeyEnvelope.open(envelope, vaultKey: key)
                guard record.id == secret.credentialID.base64URLEncodedString() else {
                    appendQuarantine(record, credentialID: secret.credentialID, to: &result)
                    store.context.delete(record)
                    didDelete = true
                    continue
                }
                let replaced = secretsForReplacement(secret, key: key)
                for entry in replaced { deletePending(credentialID: entry.credentialID) }
                record.sealed = try seal(secret, key: key)
                record.envelopeSealed = nil
                record.relyingPartyHint = nil
                record.userNameHint = nil
                record.userHandleHint = nil
                record.createdAt = secret.createdAt
                result.migrated += 1
                result.replaced.append(contentsOf: replaced)
            } catch {
                appendQuarantine(record, to: &result)
                store.context.delete(record)
                didDelete = true
            }
        }
        if result.migrated > 0 || didDelete { try? store.context.save() }
        return result
    }

    private func quarantineEnvelopeRecords() -> EnvelopeMigrationResult {
        var result = EnvelopeMigrationResult()
        var didDelete = false
        for record in records() where record.envelopeSealed != nil {
            appendQuarantine(record, to: &result)
            store.context.delete(record)
            didDelete = true
        }
        if didDelete { try? store.context.save() }
        return result
    }

    private func appendQuarantine(_ record: PasskeyRecord, credentialID: Data? = nil,
                                  to result: inout EnvelopeMigrationResult) {
        if let site = record.relyingPartyHint, !site.isEmpty {
            result.quarantinedSites.append(site)
        }
        guard let credentialID = credentialID ?? Data(base64URLEncodedString: record.id),
              let relyingParty = record.relyingPartyHint,
              let userName = record.userNameHint,
              let userHandle = record.userHandleHint else { return }
        result.quarantinedIdentities.append(
            PasskeyInfo(relyingParty: relyingParty, userName: userName, userHandle: userHandle,
                        credentialID: credentialID, createdAt: record.createdAt,
                        lastUsedAt: record.usedAt))
    }
}
