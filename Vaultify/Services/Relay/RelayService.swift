import Foundation
import os

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
        case principalUnavailable   // escrow could not be loaded
        case iCloudAuthenticationRequired // CKError.notAuthenticated, before any relay call
        /// The escrow loaded, but this vault's key can never open it (an app
        /// reinstall replaced the vault that sealed it). Recoverable only by the
        /// user choosing `resetPrincipal()`.
        case principalFromAnotherVault
        case missingDestination     // the persona's profile has no email to forward to
        case network                // transport-level failure
        /// Verified operator state (maintenance/disabled/retired) — distinct
        /// from outages and offline (INV-CAP-04); carries per-state copy.
        case capabilityBlocked(CapabilityServiceMode, retryAfter: Int?)
        case rejected(String)       // backend refused (mapped reason, for UI copy)
    }

    private static let log = Logger(subsystem: "com.bervion.vaultify", category: "relay")

    private let repository: VaultRepository
    private let session: VaultSession
    private let escrow = RelayPrincipalEscrowService()
    /// Optional-capability state sink (breaker + operator mode + health).
    /// Optional so tests without an AppEnvironment run unchanged.
    weak var capabilities: CapabilityStore?

    init(repository: VaultRepository, session: VaultSession) {
        self.repository = repository
        self.session = session
    }

    /// The reset in flight, so a second tap joins it instead of racing it.
    private var principalReset: Task<Data, Error>?

    /// Reset Private Email when this vault cannot open its principal
    /// (`RelayPrincipalEscrowService.replaceUnopenablePrincipal`). Only ever
    /// called from the user's explicit choice in a `principalFromAnotherVault`
    /// alert: aliases owned by the old principal stop being manageable.
    func resetPrincipal() async throws {
        if let running = principalReset {
            do { _ = try await running.value } catch { throw Failure.principalFailure(for: error) }
            return
        }
        guard let vaultKey = session.vaultKey else { throw Failure.vaultLocked }
        let keyBytes = vaultKey.bytes
        let reset = Task { () async throws -> Data in
            try await self.escrow.replaceUnopenablePrincipal(vaultKey: keyBytes).principalID
        }
        principalReset = reset
        defer { principalReset = nil }
        do {
            let principalID = try await reset.value
            // Entitlement attach reads this before the next signed command does.
            RelayPrincipalWireIdentity.currentB64 = principalID.base64EncodedString()
        } catch {
            let detail = error as NSError
            Self.log.error("Principal reset failed: domain=\(detail.domain, privacy: .public) code=\(detail.code)")
            throw Failure.principalFailure(for: error)
        }
        Self.log.notice("Principal reset: the escrow this vault could not open was replaced or adopted")
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

        try await send(kind: .rotateDestination, aliasID: current.localPart,
                       domainID: Self.wireDomainID(current), destination: destination,
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
            try await send(kind: .rotateDestination, aliasID: alias.localPart,
                           domainID: Self.wireDomainID(alias), destination: email,
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
        try await send(kind: .rotateDestination, aliasID: alias.localPart,
                       domainID: Self.wireDomainID(alias), destination: inbox.email,
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
            try await send(kind: .rotateDestination, aliasID: alias.localPart,
                           domainID: Self.wireDomainID(alias), destination: want,
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
                           domainID: Self.wireDomainID(alias),
                           path: "/v1/relay/aliases/\(alias.localPart)/disable")
        }
        try repository.setAliasStatus(alias, to: .disabled)
    }

    func delete(_ alias: EmailAlias) async throws {
        if alias.backendMinted || alias.status == .active {
            try await send(kind: .deleteAlias, aliasID: alias.localPart,
                           domainID: Self.wireDomainID(alias),
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

    /// Relay App Attest assertion for one command (INV-R02), binding the same
    /// canonical transcript the principal signature covers. Shadow-safe: while
    /// `attestationRequired` is false any failure is swallowed so the principal
    /// signature remains the live auth (a register bug must not brick a mutation
    /// the assertion isn't yet enforcing). Unsupported devices fail locally
    /// while assertions are required; they never get an unauthenticated bypass.
    private func relayAssertion(forTranscript transcript: Data) async throws -> RelayAttestation.Assertion? {
        guard RelayConfig.attestationEnabled else { return nil }
        RelayDiagnostics.record("stage=attestation supported=\(RelayAttestation.isSupported) environment=\(AppAttestEnvironment.current.rawValue) host=\(RelayConfig.apiBaseURL.host ?? "unknown")")
        guard RelayAttestation.isSupported else {
            if RelayConfig.attestationRequired { throw Failure.rejected("unauthorized") }
            return nil
        }
        do {
            return try await RelayAttestation.assertion(forCommandTranscript: transcript,
                                                        baseURL: RelayConfig.apiBaseURL)
        } catch {
            let detail = error as NSError
            RelayDiagnostics.record("stage=attestation phase=failed errorDomain=\(detail.domain) code=\(detail.code)")
            Self.log.error("App Attest failed: domain=\(detail.domain, privacy: .public) code=\(detail.code)")
            // Server is at `required`, so a mutation without a valid assertion is
            // rejected anyway — hard-fail locally with a clear error rather than
            // sending a request that 401s. Transport/server failures retain
            // their real category instead of blaming the device's identity.
            if RelayConfig.attestationRequired { throw Failure.attestationFailure(for: error) }
            return nil
        }
    }

    // MARK: Destination verification (DEC-DST-01)

    /// Begin (or resend) ownership verification for a forwarding inbox: sign a
    /// kind-7 command over the EXACT email (the backend derives every hash,
    /// INV-DST-N01), store the returned opaque destination id, mark it pending.
    /// Returns the backend state so the UI can show the resend countdown.
    @discardableResult
    func beginDestinationVerification(_ inbox: ForwardingInbox) async throws -> RelayAPIClient.DestinationState {
        let data = try await send(kind: .beginDestinationVerification, aliasID: nil,
                                  destination: inbox.email, path: "/v1/relay/destinations")
        let state = try decodeDestinationState(data)
        try persistVerification(inbox, state: state)
        return state
    }

    /// Poll a begun inbox's verification (read-only, budget-free). No-op if it
    /// was never begun. Persists any status change so the UI reflects `verified`.
    @discardableResult
    func refreshDestinationStatus(_ inbox: ForwardingInbox) async throws -> RelayAPIClient.DestinationState? {
        guard let id = inbox.relayDestinationID else { return nil }
        let state = try await RelayAPIClient.destinationStatus(id: id)
        try persistVerification(inbox, state: state)
        return state
    }

    private func persistVerification(_ inbox: ForwardingInbox, state: RelayAPIClient.DestinationState) throws {
        guard var live = repository.forwardingInboxes.first(where: { $0.id == inbox.id }) else { return }
        live.relayDestinationID = state.destinationId
        live.verificationStatus = DestinationVerificationStatus(rawValue: state.status) ?? .pending
        try repository.updateInbox(live)
    }

    private func decodeDestinationState(_ data: Data) throws -> RelayAPIClient.DestinationState {
        guard let state = try? JSONDecoder().decode(RelayAPIClient.DestinationState.self, from: data) else {
            throw Failure.rejected("bad_server_data")
        }
        return state
    }

    /// Translate a rotateDestination target to what the backend expects. Until
    /// the server enforces verification the raw email is sent; once
    /// `destinationRoutingRequiresVerification` flips (lockstep with the server),
    /// forwarding binds the inbox's opaque verified destination_id, and an
    /// unverified inbox is refused locally (mirrors the server's 403).
    private func routedDestination(kind: RelayCommandKind, destination: String?) throws -> String? {
        guard kind == .rotateDestination, let email = destination,
              RelayConfig.destinationRoutingRequiresVerification else { return destination }
        guard let inbox = repository.forwardingInboxes.first(where: { $0.email == email }),
              inbox.verificationStatus == .verified, let id = inbox.relayDestinationID else {
            throw Failure.rejected("destination_not_verified")
        }
        return id
    }

    /// createAlias with collision re-mint (up to 3 tries). Returns the (possibly
    /// re-minted) alias whose local-part the backend accepted.
    private func mint(_ alias: EmailAlias) async throws -> EmailAlias {
        var current = alias
        for _ in 0..<3 {
            do {
                // createAlias signs its namespace explicitly, even for the
                // legacy domain (the create is what fixes the alias's
                // externally reachable identity — never leave it implied).
                try await send(kind: .createAlias, aliasID: current.localPart,
                               domainID: current.relayDomainID,
                               path: "/v1/relay/aliases")
                return current
            } catch RelayAPIClient.Failure.aliasExists {
                current.localPart = AliasAddress.randomLocalPart()
                try repository.updateAlias(current)
                current = repository.aliases.first { $0.id == current.id } ?? current
            }
        }
        throw Failure.rejected("alias_exists")
    }

    /// Sign and send one command. Bounded silent recovery via `RelayRetryPolicy`:
    /// nonce_replay rebuilds the command (fresh nonce + issued_at, re-signed) and
    /// retries ONCE; epoch_stale refreshes the principal from the escrow first
    /// (another device rotated it) — the user sees a spinner, never epoch talk.
    /// Every attempt re-resolves the principal and signs a fresh transcript; a
    /// signature is never reused after any field changes (SEC-PE06/07).
    /// Alias-scoped commands (disable/rotate/delete) send the domain only for
    /// non-legacy aliases: absent = legacy is the server's canonical V2 shape,
    /// which keeps every pre-domain alias's traffic byte-stable. (createAlias
    /// is the exception — it must always name its namespace explicitly.)
    private static func wireDomainID(_ alias: EmailAlias) -> String? {
        alias.relayDomainID == AuxiliaryDomainRegistry.legacyEmailDomainID
            ? nil : alias.relayDomainID
    }

    @discardableResult
    private func send(kind: RelayCommandKind, aliasID: String?, domainID: String? = nil,
                      destination: String? = nil,
                      path: String, method: String = "POST") async throws -> Data {
        guard let vaultKey = session.vaultKey else { throw Failure.vaultLocked }
        // Circuit breaker: during a confirmed outage, don't burn signed requests.
        guard capabilities?.allowRequest(.privateEmail) ?? true else {
            throw Failure.capabilityBlocked(.active, retryAfter: nil)   // renders as "temporarily unavailable"
        }
        let effectiveDestination = try routedDestination(kind: kind, destination: destination)
        var attempt = 0
        while true {
            attempt += 1
            RelayDiagnostics.record("stage=command phase=begin kind=\(kind.rawValue) attempt=\(attempt)")
            let principal: RelayPrincipalIdentity
            do { principal = try await escrow.ensurePrincipal(vaultKey: vaultKey.bytes) }
            catch {
                let detail = error as NSError
                RelayDiagnostics.record("stage=escrow phase=failed errorDomain=\(detail.domain) code=\(detail.code)")
                Self.log.error("Principal escrow failed: domain=\(detail.domain, privacy: .public) code=\(detail.code)")
                throw Failure.principalFailure(for: error)
            }
            // Publish the wire identity (std-b64 WITH padding — the exact
            // `principal_id` string the server hashes) for entitlement
            // binding requests; the attach flow reads it lazily.
            RelayPrincipalWireIdentity.currentB64 = principal.principalID.base64EncodedString()

            let command = RelayCommand(principalID: principal.principalID, epoch: principal.epoch,
                                       nonce: Data(CryptoRandom.bytes(16)),
                                       issuedAtUnixMs: Int64(Date().timeIntervalSince1970 * 1000),
                                       kind: kind, aliasID: aliasID, domainID: domainID,
                                       destination: effectiveDestination)
            // V2 everywhere (dual-accept is live server-side): the namespace,
            // when present, is inside the signed bytes — never a loose field.
            let signed = try RelayCommandCanonical.signV2(command, using: principal)
            let genesisKey = RelayAPIClient.genesisPublicKey(for: principal, kind: kind)
            RelayDiagnostics.record("stage=command phase=signed kind=\(kind.rawValue) epoch=\(principal.epoch) commandVersion=2 genesisKey=\(genesisKey != nil)")
            let attest = try await relayAssertion(forTranscript: signed.transcript)

            do {
                let responseData = try await RelayAPIClient.send(
                    command, signature: signed.signature,
                    genesisPublicKey: genesisKey,
                    attestKeyId: attest?.keyId, assertionB64: attest?.assertionB64,
                    path: path, method: method)
                capabilities?.noteSuccess(.privateEmail)
                RelayDiagnostics.record("stage=command phase=succeeded kind=\(kind.rawValue) attempt=\(attempt)")
                return responseData
            } catch let failure as RelayAPIClient.Failure {
                Self.log.error("Relay command failed: kind=\(kind.rawValue) failure=\(String(describing: failure), privacy: .public)")
                if case .aliasExists = failure {
                    capabilities?.noteServiceResponded(.privateEmail)
                    throw failure  // mint's retry loop handles it
                }
                if case .entitlementRefreshRequired = failure {
                    // Lease died with an account state change (contract §4):
                    // re-attach once, then loop — the nonce was consumed, so
                    // the retry MUST re-sign with a fresh nonce, which this
                    // outer loop already does. Not a user-facing error.
                    capabilities?.noteServiceResponded(.privateEmail)
                    guard attempt < 3,
                          await LooxEntitlementClientHooks.refreshHandler?() == true else {
                        throw Failure.rejected("entitlement_refresh_required")
                    }
                    continue
                }
                if case .capability(let mode, let retryAfter) = failure {
                    // Verified operator state — persist it; the service is UP.
                    capabilities?.noteOperatorSignal(.privateEmail, .init(mode: mode, retryAfter: retryAfter))
                    throw Failure.capabilityBlocked(mode, retryAfter: retryAfter)
                }
                switch RelayRetryPolicy.action(for: failure, attempt: attempt) {
                case .retry:
                    continue
                case .reenrollThenRetry:
                    RelayDiagnostics.record("stage=attestation phase=recover reason=key_unknown attempt=\(attempt)")
                    if let rejectedKeyId = attest?.keyId {
                        RelayAttestation.resetRegistration(baseURL: RelayConfig.apiBaseURL,
                                                           rejectedKeyId: rejectedKeyId)
                    }
                    continue
                case .refreshEpochThenRetry:
                    _ = try? await escrow.refreshFromCloud(vaultKey: vaultKey.bytes)
                    continue
                case .fail("network"):
                    capabilities?.noteInfrastructureFailure(.privateEmail)
                    throw Failure.network
                case .fail(let reason):
                    // Plain 502/503/504 (no capability code) = infrastructure.
                    if reason.hasPrefix("server_5") {
                        capabilities?.noteInfrastructureFailure(.privateEmail)
                    } else {
                        capabilities?.noteServiceResponded(.privateEmail)
                    }
                    throw Failure.rejected(reason)
                }
            }
        }
    }
}
