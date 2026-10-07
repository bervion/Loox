import Foundation
import CloudKit
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
    private var busyAliases: Set<String> = []
    private var aliasWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    /// A single alias cannot be minted/rotated/deleted by two overlapping tasks.
    /// Waiting callers resolve live state after acquisition, never their old row.
    private func withAliasOperation(_ id: String, operation: () async throws -> Void) async throws {
        if busyAliases.contains(id) {
            await withCheckedContinuation { continuation in
                aliasWaiters[id, default: []].append(continuation)
            }
        } else { busyAliases.insert(id) }
        defer {
            if var waiting = aliasWaiters[id], !waiting.isEmpty {
                let first = waiting.removeFirst()
                aliasWaiters[id] = waiting.isEmpty ? nil : waiting
                first.resume()
            } else { busyAliases.remove(id) }
        }
        try Task.checkCancellation()
        try await operation()
    }

    private func liveAlias(_ snapshot: EmailAlias) throws -> EmailAlias {
        guard session.vaultKey != nil else { throw Failure.vaultLocked }
        guard let live = repository.aliases.first(where: { $0.id == snapshot.id }),
              live.personaId == snapshot.personaId, live.localPart == snapshot.localPart,
              live.relayDomainID == snapshot.relayDomainID else { throw Failure.rejected("alias_changed") }
        return live
    }

    func activate(_ alias: EmailAlias) async throws {
        try await withAliasOperation(alias.id) {
            var current = try self.liveAlias(alias)
            guard let persona = self.repository.personas.first(where: { $0.id == current.personaId }) else {
                throw Failure.rejected("no_persona")
            }
            guard let destination = self.repository.resolvedDestination(for: current) else {
                throw Failure.missingDestination
            }
            let relationRevision = current.relationRevision
            if !current.backendMinted {
                current = try await self.mint(current)
                current = try self.liveAlias(current)
                // Persist an acknowledged mint before honoring cancellation:
                // retry must route this namespace instead of creating another.
                try self.repository.markMinted(current)
                current = try self.liveAlias(current)
                try Task.checkCancellation()
            }
            if current.backendMinted && (current.status == .paused || current.status == .disabled) {
                // Route while the backend is still paused, then resume the exact
                // owned namespace. rotateDestination does not itself reactivate.
                try await self.send(kind: .rotateDestination, aliasID: current.localPart,
                                    domainID: Self.wireDomainID(current), destination: destination,
                                    path: "/v1/relay/aliases/\(current.localPart)/destination")
                try Task.checkCancellation()
                var routed = try self.liveAlias(current)
                routed.forwardingTarget = destination
                try self.repository.updateAlias(routed)
                current = try self.liveAlias(current)
                // createAlias is idempotent for an owned paused namespace. This
                // is a resume, so aliasExists must never trigger collision remint.
                try await self.send(kind: .createAlias, aliasID: current.localPart,
                                    domainID: current.relayDomainID,
                                    path: "/v1/relay/aliases")
                var resumed = try self.liveAlias(current)
                resumed.status = .active
                resumed.disabledAt = nil
                try self.repository.updateAlias(resumed)
                try Task.checkCancellation()
            } else if current.status != .active || current.forwardingTarget != destination {
                try await self.send(kind: .rotateDestination, aliasID: current.localPart,
                                    domainID: Self.wireDomainID(current), destination: destination,
                                    path: "/v1/relay/aliases/\(current.localPart)/destination")
                var live = try self.liveAlias(current)
                live.forwardingTarget = destination
                live.status = .active
                live.disabledAt = nil
                try self.repository.updateAlias(live)
                try Task.checkCancellation()
            }
            let live = try self.liveAlias(current)
            switch live.tier {
            case .persona: self.repository.attachAliasToProfile(live, persona: persona)
            case .perSite:
                // Field conflict/protection is surfaced as local recovery after
                // routing succeeds, never overwritten or reported as a mail outage.
                do { try self.repository.attachAliasToLogin(live, expectedRelationRevision: relationRevision) }
                catch let failure as VaultRepository.AliasLinkFailure { throw failure }
            }
        }
    }

    func updateDestination(for persona: Persona, to email: String) async throws {
        let profileInboxID = repository.forwardingInboxes.first {
            $0.source == .personaProfile && $0.personaId == persona.id
        }?.id
        for alias in repository.aliases(forPersona: persona.id) where alias.backendMinted {
            if let pinned = alias.forwardingInboxID, pinned != profileInboxID { continue }
            try await withAliasOperation(alias.id) {
                let current = try self.liveAlias(alias)
                // A pin/default edited while this caller waited owns the next target.
                guard self.repository.resolvedDestination(for: current) == email else { return }
                try await self.send(kind: .rotateDestination, aliasID: current.localPart,
                                    domainID: Self.wireDomainID(current), destination: email,
                                    path: "/v1/relay/aliases/\(current.localPart)/destination")
                try Task.checkCancellation()
                var live = try self.liveAlias(current)
                live.forwardingTarget = email
                try self.repository.updateAlias(live)
            }
        }
    }

    func setInbox(_ inbox: ForwardingInbox, for alias: EmailAlias) async throws {
        try await withAliasOperation(alias.id) {
            var current = try self.liveAlias(alias)
            guard let liveInbox = self.repository.inbox(id: inbox.id), liveInbox.email == inbox.email else {
                throw Failure.rejected("destination_changed")
            }
            current.forwardingInboxID = inbox.id
            try self.repository.updateAlias(current)
            guard current.backendMinted else { return }
            try await self.send(kind: .rotateDestination, aliasID: current.localPart,
                                domainID: Self.wireDomainID(current), destination: inbox.email,
                                path: "/v1/relay/aliases/\(current.localPart)/destination")
            try Task.checkCancellation()
            var live = try self.liveAlias(current)
            live.forwardingTarget = inbox.email
            try self.repository.updateAlias(live)
        }
    }

    func reconcileDestinations(progress: ((Int, Int) -> Void)? = nil) async throws {
        let pending = repository.aliasesNeedingRotation
        for (index, alias) in pending.enumerated() {
            try await withAliasOperation(alias.id) {
                let current = try self.liveAlias(alias)
                guard let want = self.repository.resolvedDestination(for: current),
                      want != current.forwardingTarget else { return }
                try await self.send(kind: .rotateDestination, aliasID: current.localPart,
                                    domainID: Self.wireDomainID(current), destination: want,
                                    path: "/v1/relay/aliases/\(current.localPart)/destination")
                try Task.checkCancellation()
                var live = try self.liveAlias(current)
                live.forwardingTarget = want
                try self.repository.updateAlias(live)
            }
            progress?(index + 1, pending.count)
        }
    }

    func disable(_ alias: EmailAlias) async throws {
        try await withAliasOperation(alias.id) {
            let current = try self.liveAlias(alias)
            if current.backendMinted || current.status == .active {
                try await self.send(kind: .disableAlias, aliasID: current.localPart,
                                    domainID: Self.wireDomainID(current),
                                    path: "/v1/relay/aliases/\(current.localPart)/disable")
            }
            try Task.checkCancellation()
            try self.repository.setAliasStatus(self.liveAlias(current), to: .disabled)
        }
    }

    func delete(_ alias: EmailAlias) async throws {
        try await withAliasOperation(alias.id) {
            let current = try self.liveAlias(alias)
            if current.backendMinted || current.status == .active {
                try await self.send(kind: .deleteAlias, aliasID: current.localPart,
                                    domainID: Self.wireDomainID(current),
                                    path: "/v1/relay/aliases/\(current.localPart)", method: "DELETE")
            }
            try Task.checkCancellation()
            try self.repository.deleteAlias(self.liveAlias(current))
        }
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
            if Self.isCancellation(error) { throw CancellationError() }
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
        guard let vaultKey = session.vaultKey?.bytes else { throw Failure.vaultLocked }
        let data = try await send(kind: .beginDestinationVerification, aliasID: nil,
                                  destination: inbox.email, path: "/v1/relay/destinations")
        try Task.checkCancellation()
        guard session.vaultKey?.bytes == vaultKey else { throw CancellationError() }
        let state = try decodeDestinationState(data)
        try repository.applyDestinationState(state, snapshot: inbox, allowDestinationChange: true)
        return state
    }

    @discardableResult
    func refreshDestinationStatus(_ inbox: ForwardingInbox) async throws -> RelayAPIClient.DestinationState? {
        guard let vaultKey = session.vaultKey?.bytes else { throw Failure.vaultLocked }
        guard let id = inbox.relayDestinationID else { return nil }
        let state = try await RelayAPIClient.destinationStatus(id: id)
        try Task.checkCancellation()
        guard session.vaultKey?.bytes == vaultKey else { throw CancellationError() }
        try repository.applyDestinationState(state, snapshot: inbox, allowDestinationChange: false)
        return state
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
                var live = try liveAlias(current)
                live.localPart = AliasAddress.randomLocalPart()
                try repository.updateAlias(live)
                current = live
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

    private static func isCancellation(_ error: any Error) -> Bool {
        Task.isCancelled || error is CancellationError
            || (error as? URLError)?.code == .cancelled
            || (error as? CKError)?.code == .operationCancelled
    }

    #if DEBUG
    struct CommandRequest: Equatable {
        let kind: RelayCommandKind
        let aliasID: String?
        let domainID: String?
        let destination: String?
        let path: String
        let method: String
    }
    var commandOverride: ((CommandRequest) async throws -> Data)?
    var principalOverride: (([UInt8]) async throws -> RelayPrincipalIdentity)?
    var assertionOverride: ((Data) async throws -> RelayAttestation.Assertion?)?
    var requestDateOverride: (() -> Date)?
    #endif

    @discardableResult
    private func send(kind: RelayCommandKind, aliasID: String?, domainID: String? = nil,
                      destination: String? = nil, path: String, method: String = "POST") async throws -> Data {
        guard let key = session.vaultKey?.bytes else { throw Failure.vaultLocked }
        try Task.checkCancellation()
        let now: Date
        #if DEBUG
        now = requestDateOverride?() ?? .now
        #else
        now = .now
        #endif
        let capabilityStore = capabilities
        let admission: UUID?
        if let capabilityStore {
            guard let token = capabilityStore.admitRelayCommand(now: now) else {
                throw Failure.capabilityBlocked(.active, retryAfter: nil)
            }
            admission = token
        } else { admission = nil }
        var outcome: CapabilityStore.RemoteStatusOutcome = .cancelled
        defer {
            if let admission { capabilityStore?.finishRelayCommand(admission, outcome: outcome) }
        }
        do {
            #if DEBUG
            if let commandOverride {
                let request = CommandRequest(kind: kind, aliasID: aliasID, domainID: domainID,
                                             destination: destination, path: path, method: method)
                let response = try await commandOverride(request)
                guard session.vaultKey?.bytes == key else { throw CancellationError() }
                outcome = .responded
                return response
            }
            #endif
            return try await sendAdmitted(kind: kind, aliasID: aliasID, domainID: domainID,
                destination: destination, path: path, method: method, report: { outcome = $0 })
        } catch {
            if Self.isCancellation(error) {
                outcome = .cancelled
                throw CancellationError()
            }
            // A local escrow/attestation failure leaves the relay outcome
            // unknown; the admitted half-open probe is released by default.
            #if DEBUG
            if let failure = error as? RelayAPIClient.Failure {
                switch failure {
                case .transport, .server(500...599): outcome = .infrastructureFailure
                case .capability(let mode, let retry): outcome = .operatorSignal(.init(mode: mode, retryAfter: retry))
                default: outcome = .responded
                }
            }
            #endif
            throw error
        }
    }

    @discardableResult
    private func sendAdmitted(kind: RelayCommandKind, aliasID: String?, domainID: String? = nil,
                              destination: String? = nil, path: String, method: String = "POST",
                              report: (CapabilityStore.RemoteStatusOutcome) -> Void) async throws -> Data {
        guard let vaultKey = session.vaultKey else { throw Failure.vaultLocked }
        let effectiveDestination = try routedDestination(kind: kind, destination: destination)
        var attempt = 0
        while true {
            try Task.checkCancellation()
            guard session.vaultKey?.bytes == vaultKey.bytes else { throw CancellationError() }
            attempt += 1
            RelayDiagnostics.record("stage=command phase=begin kind=\(kind.rawValue) attempt=\(attempt)")
            let principal: RelayPrincipalIdentity
            do {
                #if DEBUG
                if let principalOverride { principal = try await principalOverride(vaultKey.bytes) }
                else { principal = try await escrow.ensurePrincipal(vaultKey: vaultKey.bytes) }
                #else
                principal = try await escrow.ensurePrincipal(vaultKey: vaultKey.bytes)
                #endif
            } catch {
                if Self.isCancellation(error) { throw CancellationError() }
                let detail = error as NSError
                RelayDiagnostics.record("stage=escrow phase=failed errorDomain=\(detail.domain) code=\(detail.code)")
                Self.log.error("Principal escrow failed: domain=\(detail.domain, privacy: .public) code=\(detail.code)")
                throw Failure.principalFailure(for: error)
            }
            try Task.checkCancellation()
            guard session.vaultKey?.bytes == vaultKey.bytes else { throw CancellationError() }
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
            let attest: RelayAttestation.Assertion?
            #if DEBUG
            if let assertionOverride { attest = try await assertionOverride(signed.transcript) }
            else { attest = try await relayAssertion(forTranscript: signed.transcript) }
            #else
            attest = try await relayAssertion(forTranscript: signed.transcript)
            #endif
            try Task.checkCancellation()
            guard session.vaultKey?.bytes == vaultKey.bytes else { throw CancellationError() }

            do {
                let responseData = try await RelayAPIClient.send(
                    command, signature: signed.signature,
                    genesisPublicKey: genesisKey,
                    attestKeyId: attest?.keyId, assertionB64: attest?.assertionB64,
                    path: path, method: method)
                // A successful signed mutation may already have changed backend
                // state. Return its acknowledgment so the caller checkpoints it.
                // Read-only/destination callers perform their own cancellation CAS.
                guard session.vaultKey?.bytes == vaultKey.bytes else { throw CancellationError() }
                report(.responded)
                RelayDiagnostics.record("stage=command phase=succeeded kind=\(kind.rawValue) attempt=\(attempt)")
                return responseData
            } catch let failure as RelayAPIClient.Failure {
                try Task.checkCancellation()
                Self.log.error("Relay command failed: kind=\(kind.rawValue) failure=\(String(describing: failure), privacy: .public)")
                if case .aliasExists = failure {
                    report(.responded)
                    throw failure  // mint's retry loop handles it
                }
                if case .entitlementRefreshRequired = failure {
                    // Lease died with an account state change (contract §4):
                    // re-attach once, then loop — the nonce was consumed, so
                    // the retry MUST re-sign with a fresh nonce, which this
                    // outer loop already does. Not a user-facing error.
                    report(.responded)
                    guard attempt < 3,
                          await LooxEntitlementClientHooks.refreshHandler?() == true else {
                        throw Failure.rejected("entitlement_refresh_required")
                    }
                    continue
                }
                if case .capability(let mode, let retryAfter) = failure {
                    // Verified operator state — persist it; the service is UP.
                    report(.operatorSignal(.init(mode: mode, retryAfter: retryAfter)))
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
                    report(.infrastructureFailure)
                    throw Failure.network
                case .fail(let reason):
                    // Plain 502/503/504 (no capability code) = infrastructure.
                    if reason.hasPrefix("server_5") {
                        report(.infrastructureFailure)
                    } else {
                        report(.responded)
                    }
                    throw Failure.rejected(reason)
                }
            }
        }
    }
}
