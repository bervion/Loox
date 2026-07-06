import Foundation

/// Orchestrates relay alias lifecycle against the live backend: resolves the
/// Relay Principal (escrow), signs the canonical command, calls the control API,
/// and mirrors the outcome into the vault's alias records. All state changes go
/// through the repository so the UI observes them; a failed call never mutates
/// local state (the alias stays reserved/active as it was).
@MainActor final class RelayService {
    enum Failure: Error, Equatable {
        case vaultLocked
        case principalUnavailable   // escrow not reachable (no iCloud / offline)
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

    /// Activate a reserved alias on the relay. On a local-part collision the
    /// alias is re-minted (new random local-part) and retried, up to 3 attempts.
    func activate(_ alias: EmailAlias) async throws {
        var current = alias
        for _ in 0..<3 {
            do {
                try await send(kind: .createAlias, aliasID: current.localPart,
                               path: "/v1/relay/aliases", genesis: true)
                try repository.setAliasStatus(current, to: .active)
                return
            } catch RelayAPIClient.Failure.aliasExists {
                // Collision on the global namespace — re-mint and retry.
                current.localPart = AliasAddress.randomLocalPart()
                try repository.updateAlias(current)
                if let refreshed = repository.aliases.first(where: { $0.id == current.id }) {
                    current = refreshed
                }
            }
        }
        throw Failure.rejected("alias_exists")
    }

    /// Disable an alias. Active aliases are disabled on the backend first; a
    /// reserved/draft alias is local-only and needs no network.
    func disable(_ alias: EmailAlias) async throws {
        if alias.status == .active {
            try await send(kind: .disableAlias, aliasID: alias.localPart,
                           path: "/v1/relay/aliases/\(alias.localPart)/disable")
        }
        try repository.setAliasStatus(alias, to: .disabled)
    }

    /// Delete an alias. Active aliases are deleted on the backend first.
    func delete(_ alias: EmailAlias) async throws {
        if alias.status == .active {
            try await send(kind: .deleteAlias, aliasID: alias.localPart,
                           path: "/v1/relay/aliases/\(alias.localPart)", method: "DELETE")
        }
        try repository.deleteAlias(alias)
    }

    /// Disable every alias of this principal — the Erase-Vault teardown step.
    /// MUST succeed (durable backend ack) before a vault with active aliases may
    /// be erased; the caller blocks the erase on failure (privacy invariant:
    /// "erase" must not leave anonymous addresses forwarding forever).
    func disableAllForErase() async throws {
        guard repository.aliases.contains(where: { $0.status == .active }) else { return }
        try await send(kind: .disableAll, aliasID: nil, path: "/v1/relay/principal/disable-all")
        for alias in repository.aliases where alias.status == .active {
            try? repository.setAliasStatus(alias, to: .disabled)
        }
    }

    // MARK: Internals

    private func send(kind: RelayCommandKind, aliasID: String?, path: String,
                      method: String = "POST", genesis: Bool = false) async throws {
        guard let vaultKey = session.vaultKey else { throw Failure.vaultLocked }
        let principal: RelayPrincipalIdentity
        do { principal = try await escrow.ensurePrincipal(vaultKey: vaultKey.bytes) }
        catch { throw Failure.principalUnavailable }

        let command = RelayCommand(principalID: principal.principalID, epoch: principal.epoch,
                                   nonce: Data(CryptoRandom.bytes(16)),
                                   issuedAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000),
                                   kind: kind, aliasID: aliasID)
        let signature = try RelayCommandCanonical.sign(command, using: principal).signature
        // public_key rides ONLY while the principal is at genesis epoch — the
        // backend self-registers the principal on its first createAlias.
        let genesisKey = (genesis && principal.epoch == 1) ? principal.signingPublicKey : nil

        do {
            try await RelayAPIClient.send(command, signature: signature,
                                          genesisPublicKey: genesisKey, path: path, method: method)
        } catch let failure as RelayAPIClient.Failure {
            switch failure {
            case .transport: throw Failure.network
            case .aliasExists: throw failure   // handled by activate's retry loop
            case .unauthorized: throw Failure.rejected("unauthorized")
            case .nonceReplay: throw Failure.rejected("nonce_replay")
            case .epochStale: throw Failure.rejected("epoch_stale")
            case .rateLimited: throw Failure.rejected("rate_limited")
            case .server(let code): throw Failure.rejected("server_\(code)")
            }
        }
    }
}
