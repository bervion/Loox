import Foundation

/// Thin HTTPS client for the relay control API. Every mutating call carries a
/// principal-signed canonical transcript (the logical-authorization layer) and,
/// when App Attest is enabled, an assertion binding the same command
/// (`X-Loox-App-Attest-*` headers — app-instance admission, INV-R02). The server
/// verifies the assertion under `ASSERTION_MODE` (off/shadow/required).
nonisolated enum RelayAPIClient {

    enum Failure: Error, Equatable {
        case unauthorized          // 401 — bad signature / unknown principal
        /// 401 attestation_key_unknown — principal authorization succeeded,
        /// but this backend no longer has the device's App Attest enrollment.
        case attestationKeyUnknown
        case nonceReplay           // 409 nonce_replay — retry with a fresh nonce
        case epochStale            // 409 epoch_stale — refresh principal state
        case aliasExists           // 409 alias_exists — regenerate the local-part
        case aliasCapReached       // 409 alias_cap_reached — active+paused at cap; deletes free space
        case rateLimited           // 429 — user-attributable budget; honor Retry-After, never an operator state
        /// 429 quota_exceeded — the COMMERCIAL tier quota (entitlement
        /// contract §4), distinct from the abuse budget above; maps to the
        /// upsell paywall (purchases are live since 2026-10-21).
        case quotaExceeded
        /// 409 entitlement_refresh_required — the lease died with an account
        /// state change; re-attach and re-sign (fresh nonce), never a user error.
        case entitlementRefreshRequired
        /// 503 `*_capacity_reached` — a GLOBAL ceiling, not an outage: the
        /// service answered deliberately, so this must not trip the
        /// infrastructure breaker. Distinct from `capability` (operator state).
        case capacityReached(retryAfter: Int?)
        /// 403 destination_not_verified — forwarding target isn't a VERIFIED
        /// destination of this principal (server enforces DEC-DST-01). Not an
        /// outage: the user must re-confirm the inbox, not "retry the network".
        case destinationNotVerified
        /// Structured operator state (problem+json `capability_*` / 410 +
        /// X-Loox-Service-State). VERIFIED signal — the only response class
        /// allowed to move the app's operator-mode state (INV-CAP-07).
        case capability(CapabilityServiceMode, retryAfter: Int?)
        case server(Int)           // anything else non-2xx
        case transport             // network unreachable
    }

    /// Inbox-first verification and alias creation can both register a new
    /// principal. Other commands and rotated identities must never do so.
    static func genesisPublicKey(for principal: RelayPrincipalIdentity,
                                 kind: RelayCommandKind) -> Data? {
        guard principal.epoch == 1,
              kind == .createAlias || kind == .beginDestinationVerification else { return nil }
        return principal.signingPublicKey
    }

    /// JSON body per the relay contract: snake_case keys, base64 blobs. The
    /// transcript the signature covers is rebuilt server-side from these fields —
    /// they MUST mirror the signed command exactly.
    static func body(for command: RelayCommand, signature: Data, genesisPublicKey: Data?,
                     commandVersion: UInt8) -> [String: Any] {
        var body: [String: Any] = [
            "kind": Int(command.kind.rawValue),
            "principal_id": command.principalID.base64EncodedString(),
            "epoch": command.epoch,
            "nonce": command.nonce.base64EncodedString(),
            "issued_at_unix_ms": command.issuedAtUnixMs,
            "signature": signature.base64EncodedString(),
        ]
        // Wire presence must equal transcript presence: the server rebuilds
        // the exact signed bytes from these fields, so version and domain
        // ride together with the shape the signature covers.
        if commandVersion != 1 { body["command_version"] = Int(commandVersion) }
        if let aliasID = command.aliasID { body["alias_id"] = aliasID }
        if let domainID = command.domainID { body["domain_id"] = domainID }
        if let destination = command.destination { body["destination"] = destination }
        if let newKey = command.newPublicKey { body["new_public_key"] = newKey.base64EncodedString() }
        // Genesis: either alias creation or inbox-first verification registers
        // the principal with the same key that signed the command.
        if let genesisPublicKey { body["public_key"] = genesisPublicKey.base64EncodedString() }
        return body
    }

    /// POST/DELETE a signed command. Throws a mapped `Failure`. When an App
    /// Attest assertion is supplied it rides as `X-Loox-App-Attest-*` headers
    /// (the server also uses the key id as a rate dimension); the assertion binds
    /// the same canonical command the signature covers.
    @discardableResult
    static func send(_ command: RelayCommand, signature: Data, genesisPublicKey: Data? = nil,
                     attestKeyId: String? = nil, assertionB64: String? = nil,
                     path: String, method: String = "POST",
                     commandVersion: UInt8 = RelayCommandCanonical.versionV2,
                     baseURL: URL = RelayConfig.apiBaseURL) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let attestKeyId, let assertionB64 {
            request.setValue(attestKeyId, forHTTPHeaderField: "X-Loox-App-Attest-Key-Id")
            request.setValue(assertionB64, forHTTPHeaderField: "X-Loox-App-Attest-Assertion")
        }
        var jsonBody = body(for: command, signature: signature,
                            genesisPublicKey: genesisPublicKey, commandVersion: commandVersion)
        // Entitlement lease/grant ride as a TOP-LEVEL SIBLING, deliberately
        // outside the signed transcript (contract §3 — the server reads them
        // only after consumeNonce + principal verification; the frozen
        // LOOX-RELAY-AUTHZ transcript stays byte-identical). The contract
        // header is the client-capable coverage signal (§6.6).
        if let provider = LooxEntitlementClientHooks.payloadProvider,
           let entitlement = await provider("relay") {
            jsonBody["entitlement"] = entitlement
            request.setValue(LooxEntitlementConfig.contractVersion,
                             forHTTPHeaderField: LooxEntitlementConfig.contractHeader)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw Failure.transport
        }

        guard let http = response as? HTTPURLResponse else { throw Failure.transport }
        RelayDiagnostics.record("stage=api operation=command kind=\(command.kind.rawValue) http=\(http.statusCode) backendCode=\(diagnosticCode(from: data))")
        switch http.statusCode {
        case 200...299: return data
        case 401: throw unauthorizedFailure(from: data)
        case 403:
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["error"] as? String } ?? ""
            throw code == "destination_not_verified" ? Failure.destinationNotVerified : Failure.server(403)
        case 409: throw conflictFailure(from: data)
        case 429:
            // Commercial tier quota answers with an explicit code; anything
            // else stays the abuse/rate budget it always was.
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["error"] as? String } ?? ""
            throw code == "quota_exceeded" ? Failure.quotaExceeded : Failure.rateLimited
        case 410, 503:
            // Capacity ceilings answer 503 problem+json (`*_capacity_reached`):
            // a deliberate reply, so classify BEFORE the operator/infra split.
            if let capacity = capacityFailure(from: http, data: data) { throw capacity }
            if let signal = capabilitySignal(from: http, data: data) { throw signal }
            throw Failure.server(http.statusCode)   // plain 503 = infrastructure, NOT operator state
        default: throw Failure.server(http.statusCode)
        }
    }

    /// Parse the frozen capability contract: `X-Loox-Service-State` header (mode)
    /// + problem+json `code`/`retry_after_seconds`. Absent/garbled → nil, so a
    /// generic Cloudflare 503 can never masquerade as maintenance/retirement.
    static func capabilitySignal(from http: HTTPURLResponse, data: Data) -> Failure? {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let code = (body?["code"] as? String) ?? ""
        let headerState = http.value(forHTTPHeaderField: "X-Loox-Service-State")
        guard code.hasPrefix("capability_") || headerState != nil else { return nil }
        let fallbackMode: CapabilityServiceMode
        switch code {
        case "capability_retired": fallbackMode = .retired
        case "capability_maintenance": fallbackMode = .maintenance
        default: fallbackMode = .disabled
        }
        let mode = headerState.flatMap(CapabilityServiceMode.init(rawValue:)) ?? fallbackMode
        let retryAfter = (body?["retry_after_seconds"] as? Int)
            ?? http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
        return .capability(mode, retryAfter: retryAfter)
    }

    // MARK: - App Attest (relay-namespaced; separate trust state from loox-link)

    struct AttestChallenge: Decodable {
        let challengeId: String
        let challenge: String   // base64url, 256-bit; consumed only at register
        enum CodingKeys: String, CodingKey { case challengeId = "challenge_id"; case challenge }
    }

    /// `POST /v1/relay/attestation/challenges` → single-use challenge (201).
    static func attestChallenge(baseURL: URL = RelayConfig.apiBaseURL) async throws -> AttestChallenge {
        var request = URLRequest(url: baseURL.appending(path: "/v1/relay/attestation/challenges"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, _) = try await perform(request, operation: "challenge")
        return try JSONDecoder().decode(AttestChallenge.self, from: data)
    }

    /// `POST /v1/relay/attestation/register` → 204. Idempotent per key+backend.
    static func registerAttestation(attestationObjectB64: String, challengeId: String, keyId: String,
                                    baseURL: URL = RelayConfig.apiBaseURL) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/v1/relay/attestation/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(challengeId, forHTTPHeaderField: "X-Loox-Challenge-Id")
        request.setValue(keyId, forHTTPHeaderField: "X-Loox-App-Attest-Key-Id")
        request.httpBody = try JSONEncoder().encode(["attestation_object_b64": attestationObjectB64])
        _ = try await perform(request, operation: "register")
    }

    // MARK: - Destination verification (DEC-DST-01)

    /// Backend state of a forwarding destination. `maskedEmail` absent when
    /// revoked (plaintext scrubbed); `resendAfterSeconds` present only while
    /// pending (0 = the next signed begin/resend will actually send mail).
    struct DestinationState: Decodable {
        let destinationId: String
        let status: String            // pending | verified | revoked
        let maskedEmail: String?
        let resendAfterSeconds: Int?
        enum CodingKeys: String, CodingKey {
            case destinationId = "destination_id"
            case status
            case maskedEmail = "masked_email"
            case resendAfterSeconds = "resend_after_seconds"
        }
    }

    enum DestinationStatusFailure: Error, Equatable {
        case throttled(retryAfter: Int)
        case retryLater(statusCode: Int, retryAfter: Int)
        case malformed
    }

    /// The opaque destination ID is the read capability. The caller still
    /// enforces the app-wide rolling request budget and server Retry-After.
    /// Unknown id → 404 (indistinguishable `not_found`).
    static func destinationStatus(id: String, baseURL: URL = RelayConfig.apiBaseURL) async throws -> DestinationState {
        var request = URLRequest(url: baseURL.appending(path: "/v1/relay/destinations/\(id)"))
        request.httpMethod = "GET"
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw Failure.transport
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw Failure.transport }
        if http.statusCode == 429 {
            throw DestinationStatusFailure.throttled(retryAfter: retryAfter(from: http) ?? 60)
        }
        if let signal = capabilitySignal(from: http, data: data), !(200...299).contains(http.statusCode) {
            throw signal
        }
        guard (200...299).contains(http.statusCode) else {
            if let retry = retryAfter(from: http) {
                throw DestinationStatusFailure.retryLater(statusCode: http.statusCode, retryAfter: retry)
            }
            throw Failure.server(http.statusCode)
        }
        guard let state = try? JSONDecoder().decode(DestinationState.self, from: data),
              state.destinationId == id,
              let status = DestinationVerificationStatus(rawValue: state.status), status != .unverified else {
            throw DestinationStatusFailure.malformed
        }
        return state
    }

    static func retryAfter(from http: HTTPURLResponse, now: Date = .now) -> Int? {
        guard let value = http.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = Int(value) { return max(0, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value).map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) }
    }

    /// Shared 2xx-or-throw round trip for the attest endpoints.
    private static func perform(_ request: URLRequest, operation: String) async throws -> (Data, HTTPURLResponse) {
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            RelayDiagnostics.record("stage=api operation=\(operation) failure=transport")
            throw Failure.transport
        }
        guard let http = response as? HTTPURLResponse else { throw Failure.transport }
        RelayDiagnostics.record("stage=api operation=\(operation) http=\(http.statusCode) backendCode=\(diagnosticCode(from: data))")
        guard (200...299).contains(http.statusCode) else { throw Failure.server(http.statusCode) }
        return (data, http)
    }

    /// Generic 401s must never cause key churn. Only the explicit enrollment
    /// loss signal earns one fresh key, without changing the relay principal.
    static func unauthorizedFailure(from data: Data) -> Failure {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return body?["error"] as? String == "attestation_key_unknown" ? .attestationKeyUnknown : .unauthorized
    }

    /// Never log response bodies or arbitrary server strings: even an error
    /// payload can contain personal data. Unknown protocol codes are redacted.
    static func diagnosticCode(from data: Data) -> String {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let code = (body["error"] as? String) ?? (body["code"] as? String) else { return "none" }
        let allowed: Set<String> = [
            "unauthorized", "principal_unknown", "genesis_required", "principal_id_mismatch", "bad_signature",
            "epoch_stale", "nonce_replay", "key_unknown", "attestation_key_unknown", "attestation_required",
            "assertion_missing", "assertion_invalid", "assertion_signature_invalid", "counter_replay",
            "challenge_unknown", "challenge_expired", "challenge_used", "invalid_attestation",
            "invalid_app_id", "environment_mismatch", "rate_limited", "destination_not_verified",
            "challenge_invalid", "key_id_mismatch", "attestation_failed", "app_id_mismatch",
            "nonce_mismatch", "nonce_extension_missing", "cert_chain_invalid", "not_apple_rooted",
            "cbor_parse", "authdata_parse", "cose_key_parse", "bad_fmt", "counter_not_zero",
            "no_attested_credential", "principal_suspended", "verification_unavailable",
            "invalid_destination", "destination_rate_limited",
            "quota_exceeded", "entitlement_refresh_required", "alias_exists", "alias_cap_reached",
            "capability_disabled", "capability_maintenance", "capability_retired",
        ]
        return allowed.contains(code) ? code : "unrecognized"
    }

    /// 503 problem+json capacity codes (e.g. `global_create_capacity_reached`):
    /// a global ceiling, deliberately answered — never breaker/operator input.
    private static func capacityFailure(from http: HTTPURLResponse, data: Data) -> Failure? {
        let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let code = body?["code"] as? String, code.hasSuffix("_capacity_reached") else { return nil }
        let retryAfter = (body?["retry_after_seconds"] as? Int)
            ?? http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
        return .capacityReached(retryAfter: retryAfter)
    }

    private static func conflictFailure(from data: Data) -> Failure {
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { $0?["error"] as? String } ?? ""
        switch code {
        case "entitlement_refresh_required": return .entitlementRefreshRequired
        case "nonce_replay": return .nonceReplay
        case "epoch_stale": return .epochStale
        case "alias_exists": return .aliasExists
        case "alias_cap_reached": return .aliasCapReached
        default: return .server(409)
        }
    }
}
