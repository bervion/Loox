import Foundation
import SwiftData

/// Forwarding-inbox sealing, load, CRUD, derivation, and destination
/// resolution. Inboxes are the user's OWN real inboxes (vault-global for
/// manual ones), so they are not persona-partitioned like aliases — but a
/// strictAnonymous persona still never *surfaces* another persona's derived
/// profile inbox as a suggestion (resolution below is explicit, not fuzzy).
extension VaultRepository {

    // MARK: Load / seal

    func sealInbox(_ inbox: ForwardingInbox, key: SecureBytes) throws -> Data {
        try AESGCM.seal(JSONEncoder().encode(inbox.secret), key: key)
    }

    private func decryptInbox(_ record: ForwardingInboxRecord, key: SecureBytes) throws -> ForwardingInbox {
        let secret = try JSONDecoder().decode(ForwardingInboxSecret.self,
                                              from: AESGCM.open(record.sealed, key: key))
        return ForwardingInbox(id: record.id,
                               email: secret.email,
                               label: secret.label,
                               source: secret.source,
                               personaId: secret.personaId,
                               isDefault: secret.isDefault,
                               relayDestinationID: secret.relayDestinationID,
                               verificationStatus: secret.verificationStatus,
                               sortIndex: record.sortIndex,
                               createdAt: record.createdAt,
                               updatedAt: record.updatedAt)
    }

    func loadInboxes(key: SecureBytes) -> [ForwardingInbox] {
        let descriptor = FetchDescriptor<ForwardingInboxRecord>(predicate: #Predicate { $0.deletedAt == nil })
        guard let records = try? store.context.fetch(descriptor) else { return [] }
        return records
            .compactMap { try? decryptInbox($0, key: key) }
            .sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }

    // MARK: Resolution

    func inbox(id: String) -> ForwardingInbox? {
        forwardingInboxes.first { $0.id == id }
    }

    /// The inbox NEW aliases of this persona default to: the explicit vault-wide
    /// default if the user set one, else the persona's derived profile inbox.
    func defaultInbox(for persona: Persona) -> ForwardingInbox? {
        if let explicit = forwardingInboxes.first(where: { $0.isDefault }) { return explicit }
        return forwardingInboxes.first { $0.source == .personaProfile && $0.personaId == persona.id }
    }

    /// The real email an alias forwards to: its explicit inbox override, else its
    /// persona's default inbox, else the persona's profile email (fallback for a
    /// vault that predates inboxes). nil → the UI must ask for an email first.
    func resolvedDestination(for alias: EmailAlias) -> String? {
        if let id = alias.forwardingInboxID, let chosen = inbox(id: id) { return chosen.email }
        guard let persona = personas.first(where: { $0.id == alias.personaId }) else { return nil }
        return defaultInbox(for: persona)?.email ?? destinationEmail(for: persona)
    }

    /// Destination a NEW alias of this persona would get — the create-guard check.
    func newAliasDestination(for persona: Persona) -> String? {
        defaultInbox(for: persona)?.email ?? destinationEmail(for: persona)
    }

    /// Backend-known aliases whose resolved destination differs from what the
    /// backend last had (`forwardingTarget`). This IS the bulk-rotation batch:
    /// forwardingTarget is checkpointed per alias after each rotate, so the set
    /// shrinks as rotations land and a retry/relaunch resumes exactly the
    /// stragglers — no separate journal to desync.
    var aliasesNeedingRotation: [EmailAlias] {
        aliases.filter { alias in
            guard alias.backendMinted, alias.status != .disabled,
                  let want = resolvedDestination(for: alias) else { return false }
            return alias.forwardingTarget != want
        }
    }

    // MARK: Derivation (runs inside reload — patches state in place, never reload())

    /// One `.personaProfile` inbox per persona that has a profile email; the
    /// inbox's email follows the profile. Idempotent: repeated reloads converge.
    func ensureProfileInboxes(key: SecureBytes) {
        for persona in personas {
            guard let email = destinationEmail(for: persona) else { continue }
            if let existing = forwardingInboxes.first(where: {
                $0.source == .personaProfile && $0.personaId == persona.id
            }) {
                guard existing.email != email else { continue }
                var updated = existing
                updated.email = email
                try? persistInbox(updated, key: key)
            } else {
                let inbox = ForwardingInbox(email: email, source: .personaProfile,
                                            personaId: persona.id,
                                            sortIndex: (forwardingInboxes.map(\.sortIndex).max() ?? -1) + 1)
                let record = ForwardingInboxRecord(id: inbox.id,
                                                   sealed: (try? sealInbox(inbox, key: key)) ?? Data(),
                                                   sortIndex: inbox.sortIndex)
                guard !record.sealed.isEmpty else { continue }
                store.context.insert(record)
                try? store.context.save()
                forwardingInboxes.append(inbox)
            }
        }
    }

    // MARK: CRUD

    @discardableResult
    func addManualInbox(email: String, label: String? = nil) throws -> String {
        guard let key = session.vaultKey else { throw AuthError.locked }
        let inbox = ForwardingInbox(email: email, label: label, source: .manual,
                                    sortIndex: (forwardingInboxes.map(\.sortIndex).max() ?? -1) + 1)
        let record = ForwardingInboxRecord(id: inbox.id,
                                           sealed: try sealInbox(inbox, key: key),
                                           sortIndex: inbox.sortIndex)
        store.context.insert(record)
        try store.context.save()
        reload()
        noteLocalMutation()
        return inbox.id
    }

    func updateInbox(_ inbox: ForwardingInbox) throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        try persistInbox(inbox, key: key)
        reload()
        noteLocalMutation()
    }

    /// Make one inbox the vault-wide default for new aliases (clears the flag on
    /// every other inbox — at most one default).
    func setDefaultInbox(_ inbox: ForwardingInbox) throws {
        guard let key = session.vaultKey else { throw AuthError.locked }
        for other in forwardingInboxes where other.isDefault && other.id != inbox.id {
            var cleared = other
            cleared.isDefault = false
            try persistInbox(cleared, key: key)
        }
        var updated = inbox
        updated.isDefault = true
        try persistInbox(updated, key: key)
        reload()
        noteLocalMutation()
    }

    /// Tombstone a manual inbox. Refused while any live alias still points at it
    /// (the caller must re-point or delete those aliases first) and for derived
    /// profile inboxes (they follow the profile email instead).
    func deleteInbox(_ inbox: ForwardingInbox) throws {
        guard inbox.source == .manual else { return }
        guard !aliases.contains(where: { $0.forwardingInboxID == inbox.id }) else { return }
        guard let record = store.inboxRecord(id: inbox.id) else { return }
        record.deletedAt = .now
        record.updatedAt = .now
        record.dirty = true
        try store.context.save()
        reload()
        noteLocalMutation()
    }

    // MARK: Internals

    /// Re-seal + bump `updatedAt` (whole-record LWW) and patch the in-memory
    /// cache in place — safe to call from within reload-time derivation.
    private func persistInbox(_ inbox: ForwardingInbox, key: SecureBytes) throws {
        guard let record = store.inboxRecord(id: inbox.id) else { return }
        var updated = inbox
        updated.updatedAt = .now
        record.sealed = try sealInbox(updated, key: key)
        record.sortIndex = updated.sortIndex
        record.updatedAt = updated.updatedAt
        record.dirty = true
        try store.context.save()
        if let index = forwardingInboxes.firstIndex(where: { $0.id == updated.id }) {
            forwardingInboxes[index] = updated
        }
    }
}
