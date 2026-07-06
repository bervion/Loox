import Foundation

/// Orchestrates relay alias lifecycle against the live backend: resolves the
/// Relay Principal (escrow), signs the canonical command, calls the control API,
/// and mirrors the outcome into the vault. Local state changes only after a
/// backend success — a failed call never lies about what is live.
///
/// "Create an alias" is two backend calls: createAlias (mint) then
/// rotateDestination (set the persona's real email). The mint is checkpointed
/// (`backendMinted`) so a failure between the two is resumable without orphaning.
@MainActor final class RelayService {
    enum Failure: Error, Equatable {
        case vaultLocked
        case principalUnavailable   // escrow not reachable (no iCloud / offline)
        case missingDestination     // the persona's profile has no email to forward to
        case network                // transport-level failure
        case rejected(String)       // backend refused (mapped reason, for UI copy)
    }

    private let repository: VaultRepository
    private let session: VaultSession
    private let escrow = RelayPrincipalEscrowService()

    init(repository: VaultRepository, session: VaultSession) {
        self.repository = repository
        self.session = session
    }

    /// Activate a reserved alias: mint it (if not already), point it at the
    /// owning persona's real email, mark it active, and write the address back
    /// onto the profile/login. Resumable: a retry after a mint resumes at
    /// rotateDestination rather than re-minting.
    func activate(_ alias: EmailAlias) async throws {
        guard let persona = repository.personas.first(where: { $0.id == alias.personaId }) else {
            throw Failure.rejected("no_persona")
        }
        // Explicit per-alias inbox wins; else the persona's default inbox; else
        // the profile email (pre-inbox vaults).
        guard let destination = repository.resolvedDestination(for: alias) else {
            throw Failure.missingDestination
        }

        var current = alias
        if !current.backendMinted {
            current = try await mint(current)      // createAlias (+ collision re-mint)
            try repository.markMinted(current)
            current = repository.aliases.first { $0.id == current.id } ?? current
        }

        try await send(kind: .rotateDestination, aliasID: current.localPart, destination: destination,
                       path: "/v1/relay/aliases/\(current.localPart)/destination")

        var activated = current
        activated.forwardingTarget = destination
        try repository.updateAlias(activated)
        if let refreshed = repository.aliases.first(where: { $0.id == activated.id }) {
            try repository.setAliasStatus(refreshed, to: .active)
        }
        // Write-back is non-fatal — the backend state is already correct.
        if let live = repository.aliases.first(where: { $0.id == activated.id }) {
            switch live.tier {
            case .persona: repository.attachAliasToProfile(live, persona: persona)
            case .perSite: repository.attachAliasToLogin(live)
            }
        }
    }

    /// Change a persona's real email: re-point every one of its aliases that the
    /// backend knows about to the new destination — EXCEPT aliases pinned to a
    /// different explicit inbox (their destination is their own choice).
    /// Sequential + idempotent — a retry finishes any that didn't rotate.
    func updateDestination(for persona: Persona, to email: String) async throws {
        let profileInboxID = repository.forwardingInboxes.first {
            $0.source == .personaProfile && $0.personaId == persona.id
        }?.id
        for alias in repository.aliases(forPersona: persona.id) where alias.backendMinted {
            if let pinned = alias.forwardingInboxID, pinned != profileInboxID { continue }
            try await send(kind: .rotateDestination, aliasID: alias.localPart, destination: email,
                           path: "/v1/relay/aliases/\(alias.localPart)/destination")
            var updated = alias
            updated.forwardingTarget = email
            try repository.updateAlias(updated)
        }
    }

    /// Pin an alias to an inbox, then rotate it on the backend. The pin persists
    /// FIRST (durable intent): if the rotate fails, the alias lands in
    /// `aliasesNeedingRotation` and the next reconcile finishes the job.
    func setInbox(_ inbox: ForwardingInbox, for alias: EmailAlias) async throws {
        var pinned = alias
        pinned.forwardingInboxID = inbox.id
        try repository.updateAlias(pinned)
        guard alias.backendMinted else { return }
        try await send(kind: .rotateDestination, aliasID: alias.localPart, destination: inbox.email,
                       path: "/v1/relay/aliases/\(alias.localPart)/destination")
        if var live = repository.aliases.first(where: { $0.id == alias.id }) {
            live.forwardingTarget = inbox.email
            try repository.updateAlias(live)
        }
    }

    /// Rotate every alias whose resolved destination drifted from the backend
    /// (default-inbox change, inbox email edit…). Sequential; `forwardingTarget`
    /// checkpoints after each success, so an interruption resumes exactly the
    /// stragglers. NOT atomic — progress is surfaced, never pretended away.
    func reconcileDestinations(progress: ((Int, Int) -> Void)? = nil) async throws {
        let pending = repository.aliasesNeedingRotation
        for (index, alias) in pending.enumerated() {
            guard let want = repository.resolvedDestination(for: alias) else { continue }
            try await send(kind: .rotateDestination, aliasID: alias.localPart, destination: want,
                           path: "/v1/relay/aliases/\(alias.localPart)/destination")
            if var live = repository.aliases.first(where: { $0.id == alias.id }) {
                live.forwardingTarget = want
                try repository.updateAlias(live)
            }
            progress?(index + 1, pending.count)
        }
    }

    func disable(_ alias: EmailAlias) async throws {
        if alias.backendMinted || alias.status == .active {
            try await send(kind: .disableAlias, aliasID: alias.localPart,
                           path: "/v1/relay/aliases/\(alias.localPart)/disable")
        }
        try repository.setAliasStatus(alias, to: .disabled)
    }

    func delete(_ alias: EmailAlias) async throws {
        if alias.backendMinted || alias.status == .active {
            try await send(kind: .deleteAlias, aliasID: alias.localPart,
                           path: "/v1/relay/aliases/\(alias.localPart)", method: "DELETE")
        }
        try repository.deleteAlias(alias)
    }

    /// Disable every alias of this principal — the Erase-Vault teardown step. MUST
    /// succeed (durable backend ack) before a vault with active aliases is erased.
    func disableAllForErase() async throws {
        guard repository.aliases.contains(where: { $0.status == .active }) else { return }
        try await send(kind: .disableAll, aliasID: nil, path: "/v1/relay/principal/disable-all")
        for alias in repository.aliases where alias.status == .active {
            try? repository.setAliasStatus(alias, to: .disabled)
        }
    }

    // MARK: Internals

    /// createAlias with collision re-mint (up to 3 tries). Returns the (possibly
    /// re-minted) alias whose local-part the backend accepted.
    private func mint(_ alias: EmailAlias) async throws -> EmailAlias {
        var current = alias
        for _ in 0..<3 {
            do {
                try await send(kind: .createAlias, aliasID: current.localPart,
                               path: "/v1/relay/aliases", genesis: true)
                return current
            } catch RelayAPIClient.Failure.aliasExists {
                current.localPart = AliasAddress.randomLocalPart()
                try repository.updateAlias(current)
                current = repository.aliases.first { $0.id == current.id } ?? current
            }
        }
        throw Failure.rejected("alias_exists")
    }

    private func send(kind: RelayCommandKind, aliasID: String?, destination: String? = nil,
                      path: String, method: String = "POST", genesis: Bool = false) async throws {
        guard let vaultKey = session.vaultKey else { throw Failure.vaultLocked }
        let principal: RelayPrincipalIdentity
        do { principal = try await escrow.ensurePrincipal(vaultKey: vaultKey.bytes) }
        catch { throw Failure.principalUnavailable }

        let command = RelayCommand(principalID: principal.principalID, epoch: principal.epoch,
                                   nonce: Data(CryptoRandom.bytes(16)),
                                   issuedAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000),
                                   kind: kind, aliasID: aliasID, destination: destination)
        let signature = try RelayCommandCanonical.sign(command, using: principal).signature
        let genesisKey = (genesis && principal.epoch == 1) ? principal.signingPublicKey : nil

        do {
            try await RelayAPIClient.send(command, signature: signature,
                                          genesisPublicKey: genesisKey, path: path, method: method)
        } catch let failure as RelayAPIClient.Failure {
            switch failure {
            case .transport: throw Failure.network
            case .aliasExists: throw failure   // handled by mint's retry loop
            case .unauthorized: throw Failure.rejected("unauthorized")
            case .nonceReplay: throw Failure.rejected("nonce_replay")
            case .epochStale: throw Failure.rejected("epoch_stale")
            case .rateLimited: throw Failure.rejected("rate_limited")
            case .server(let code): throw Failure.rejected("server_\(code)")
            }
        }
    }
}
