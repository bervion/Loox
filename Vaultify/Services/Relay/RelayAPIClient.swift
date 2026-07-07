import Foundation

/// Thin HTTPS client for the relay control API. Every mutating call carries a
/// principal-signed canonical transcript (the logical-authorization layer) and,
/// when App Attest is enabled, an assertion binding the same command
/// (`X-Loox-App-Attest-*` headers — app-instance admission, INV-R02). The server
/// verifies the assertion under `ASSERTION_MODE` (off/shadow/required).
nonisolated enum RelayAPIClient {

    enum Failure: Error, Equatable {
        case unauthorized          // 401 — bad signature / unknown principal
        case nonceReplay           // 409 nonce_replay — retry with a fresh nonce
        case epochStale            // 409 epoch_stale — refresh principal state
        case aliasExists           // 409 alias_exists — regenerate the local-part
        case aliasCapReached       // 409 alias_cap_reached — active+paused at cap; deletes free space
        case rateLimited           // 429 — user-attributable budget; honor Retry-After, never an operator state
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

    /// JSON body per the relay contract: snake_case keys, base64 blobs. The
    /// transcript the signature covers is rebuilt server-side from these fields —
    /// they MUST mirror the signed command exactly.
    static func body(for command: RelayCommand, signature: Data, genesisPublicKey: Data?) -> [String: Any] {
        var body: [String: Any] = [
            "kind": Int(command.kind.rawValue),
            "principal_id": command.principalID.base64EncodedString(),
            "epoch": command.epoch,
            "nonce": command.nonce.base64EncodedString(),
            "issued_at_unix_ms": command.issuedAtUnixMs,
            "signature": signature.base64EncodedString(),
        ]
        if let aliasID = command.aliasID { body["alias_id"] = aliasID }
        if let destination = command.destination { body["destination"] = destination }
        if let newKey = command.newPublicKey { body["new_public_key"] = newKey.base64EncodedString() }
        // Genesis only: the first createAlias registers the principal.
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
                     baseURL: URL = RelayConfig.apiBaseURL) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let attestKeyId, let assertionB64 {
            request.setValue(attestKeyId, forHTTPHeaderField: "X-Loox-App-Attest-Key-Id")
            request.setValue(assertionB64, forHTTPHeaderField: "X-Loox-App-Attest-Assertion")
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body(for: command, signature: signature, genesisPublicKey: genesisPublicKey))

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw Failure.transport }

        guard let http = response as? HTTPURLResponse else { throw Failure.transport }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw Failure.unauthorized
        case 403:
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["error"] as? String } ?? ""
            throw code == "destination_not_verified" ? Failure.destinationNotVerified : Failure.server(403)
        case 409: throw conflictFailure(from: data)
        case 429: throw Failure.rateLimited
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
        let (data, response) = try await perform(request)
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
        _ = try await perform(request)
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

    /// `GET /v1/relay/destinations/{id}` — read-only, budget-free (the opaque
    /// 128-bit id is the read capability; no signed command). Poll freely.
    /// Unknown id → 404 (indistinguishable `not_found`).
    static func destinationStatus(id: String, baseURL: URL = RelayConfig.apiBaseURL) async throws -> DestinationState {
        var request = URLRequest(url: baseURL.appending(path: "/v1/relay/destinations/\(id)"))
        request.httpMethod = "GET"
        let (data, response) = try await perform(request)
        _ = response
        return try JSONDecoder().decode(DestinationState.self, from: data)
    }

    /// Shared 2xx-or-throw round trip for the attest endpoints.
    private static func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw Failure.transport }
        guard let http = response as? HTTPURLResponse else { throw Failure.transport }
        guard (200...299).contains(http.statusCode) else { throw Failure.server(http.statusCode) }
        return (data, http)
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
        case "nonce_replay": return .nonceReplay
        case "epoch_stale": return .epochStale
        case "alias_exists": return .aliasExists
        case "alias_cap_reached": return .aliasCapReached
        default: return .server(409)
        }
    }
}
