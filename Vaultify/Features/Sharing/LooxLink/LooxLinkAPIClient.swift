import Foundation

/// Errors surfaced by the Loox Link API. `notFound` is deliberately vague —
/// the server keeps unknown/expired/revoked indistinguishable (404) by design.
nonisolated enum LooxLinkAPIError: Error, LocalizedError, Sendable {
    case invalidResponse
    case unauthorized
    case payloadTooLarge
    case notFound
    /// Verified operator state (problem+json `capability_*` / 410 + header) —
    /// distinct copy per mode; never inferred from plain 404/timeout (INV-CAP-07).
    case capability(CapabilityServiceMode, retryAfter: Int?)
    case server(status: Int, code: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: appString("The share service sent an unexpected response.")
        case .unauthorized: appString("This app couldn't prove it's a genuine Loox install. Try again later.")
        case .payloadTooLarge: appString("This item is too large to share as a link.")
        case .notFound: appString("This link no longer exists.")
        case .capability(.maintenance, _): appString("Creating and managing links is temporarily paused. Your vault continues to work normally.")
        case .capability(.retired, _): appString("Share Links are no longer offered. Your saved vault items are unchanged.")
        case .capability: appString("Share Links are temporarily unavailable. Your vault is not affected.")
        case .server(let status, let code): appString("Share service error (\(code ?? String(status))).")
        }
    }
}

nonisolated struct LooxLinkChallenge: Decodable, Sendable {
    let challengeId: String
    /// base64url raw challenge bytes; single-use, ~180 s TTL.
    let challenge: String

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id", challenge
    }
}

nonisolated struct LooxLinkCreateResponse: Decodable, Sendable {
    let shareId: String
    let revokeToken: String
    /// Unix seconds.
    let expiresAt: Int64
    /// Single-purpose credential for the optional shorten step (deliberately
    /// NOT the revoke token — possession of "make this prettier" must never
    /// equal possession of "kill this link"). Absent until the backend ships
    /// the shortener, which is what hides the Shorten action client-side.
    let shortenToken: String?

    enum CodingKeys: String, CodingKey {
        case shareId = "share_id", revokeToken = "revoke_token", expiresAt = "expires_at"
        case shortenToken = "shorten_token"
    }
}

nonisolated struct LooxLinkShortenResponse: Decodable, Sendable {
    /// Fragment-free short URL — the backend picks the host; the app never
    /// chooses a short-link domain and reattaches the fragment locally.
    let shortURL: String
    let domainID: String

    enum CodingKeys: String, CodingKey {
        case shortURL = "short_url", domainID = "domain_id"
    }
}

/// Thin URLSession client for the Loox Link Worker (see openapi.yaml).
/// The request body only ever carries ciphertext — the content key never
/// appears in any request, header, or log.
nonisolated struct LooxLinkAPIClient: Sendable {
    struct AssertionHeaders: Sendable {
        let challengeId: String
        let keyId: String
        let assertionB64: String
    }

    var baseURL: URL { LooxLinkConfig.apiBase }

    func getChallenge() async throws -> LooxLinkChallenge {
        try await post(path: "/v1/attestation/challenges", body: nil, decode: LooxLinkChallenge.self)
    }

    /// Registers an App Attest key (idempotent per key). 204 on success.
    func register(attestationObjectB64: String, challengeId: String, keyId: String) async throws {
        var request = makeRequest(path: "/v1/attestation/register")
        request.setValue(challengeId, forHTTPHeaderField: "X-Loox-Challenge-Id")
        request.setValue(keyId, forHTTPHeaderField: "X-Loox-App-Attest-Key-Id")
        request.httpBody = try JSONEncoder().encode(["attestation_object_b64": attestationObjectB64])
        do {
            _ = try await send(request)
        } catch LooxLinkAPIError.notFound {
            // 404 here is a route/deploy gap, never a missing link — remap so
            // the UI can't surface "this link no longer exists" during setup.
            throw LooxLinkAPIError.server(status: 404, code: "not_found")
        }
    }

    func createShare(ciphertextB64: String, ivB64: String, expiresInSeconds: UInt64,
                     oneTime: Bool, assertion: AssertionHeaders?) async throws -> LooxLinkCreateResponse {
        var request = makeRequest(path: LooxLinkCanonical.createSharePath)
        // Interim anti-abuse token, required until App Attest is the real
        // auth (the Worker checks it only when APP_CREATE_TOKEN is set).
        if let appToken = LooxLinkConfig.appToken {
            request.setValue(appToken, forHTTPHeaderField: "X-Loox-App-Token")
        }
        if let assertion {
            request.setValue(assertion.challengeId, forHTTPHeaderField: "X-Loox-Challenge-Id")
            request.setValue(assertion.keyId, forHTTPHeaderField: "X-Loox-App-Attest-Key-Id")
            request.setValue(assertion.assertionB64, forHTTPHeaderField: "X-Loox-App-Attest-Assertion")
        }
        // Keys must exactly match what the Worker binds into the canonical
        // transcript; `envelope` (encrypted display metadata) is unused in V1.
        var body: [String: AnyEncodableValue] = [
            "ciphertext": .string(ciphertextB64),
            "iv": .string(ivB64),
            "crypto_version": .int(Int(LooxLinkConfig.cryptoVersion)),
            "expires_in_seconds": .int(Int(expiresInSeconds)),
            "envelope": .null,
        ]
        // Always explicit: the V2 assertion transcript binds one_time (absent
        // in the body = false on the verifier), so the wire must never be
        // ambiguous about the burn-after-read flag.
        body["one_time"] = .bool(oneTime)
        request.httpBody = try JSONEncoder().encode(body)
        if let count = request.httpBody?.count, count > LooxLinkConfig.maxBodyBytes {
            throw LooxLinkAPIError.payloadTooLarge
        }
        do {
            let data = try await send(request)
            return try decodeOrThrow(LooxLinkCreateResponse.self, from: data)
        } catch LooxLinkAPIError.notFound {
            // A 404 on CREATE is a routing/deploy problem, never a missing
            // link — remap so the UI can't show "this link no longer exists".
            throw LooxLinkAPIError.server(status: 404, code: "not_found")
        }
    }

    /// Mint a short presentation link for an existing share. The request
    /// carries only the share id and the single-purpose shorten token — never
    /// the canonical URL, so the fragment key cannot reach the backend by
    /// construction. Wrong/unknown token or id → indistinguishable 404.
    func createShortLink(shareId: String, shortenToken: String,
                         assertion: AssertionHeaders?) async throws -> LooxLinkShortenResponse {
        var request = makeRequest(path: LooxLinkConfig.shortenPath)
        if let assertion {
            request.setValue(assertion.challengeId, forHTTPHeaderField: "X-Loox-Challenge-Id")
            request.setValue(assertion.keyId, forHTTPHeaderField: "X-Loox-App-Attest-Key-Id")
            request.setValue(assertion.assertionB64, forHTTPHeaderField: "X-Loox-App-Attest-Assertion")
        }
        request.httpBody = try JSONEncoder().encode(["share_id": shareId,
                                                     "shorten_token": shortenToken])
        let data = try await send(request)
        return try decodeOrThrow(LooxLinkShortenResponse.self, from: data)
    }

    /// 204 on success; wrong/unknown token or id → indistinguishable 404.
    func revoke(shareId: String, revokeToken: String) async throws {
        var request = makeRequest(path: "/v1/shares/\(shareId)/revoke")
        request.httpBody = try JSONEncoder().encode(["revoke_token": revokeToken])
        _ = try await send(request)
    }

    // MARK: - Plumbing

    private func post<T: Decodable>(path: String, body: Data?, decode: T.Type) async throws -> T {
        var request = makeRequest(path: path)
        request.httpBody = body
        let data = try await send(request)
        return try decodeOrThrow(T.self, from: data)
    }

    private func makeRequest(path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LooxLinkAPIError.invalidResponse }
        #if DEBUG
        // Path + status only — never bodies, tokens, or anything URL-fragment
        // shaped (the content key never reaches this layer by design).
        let errorCode = http.statusCode >= 400
            ? ((try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "") : ""
        print("[LooxLink] \(request.httpMethod ?? "?") \(request.url?.path ?? "?") → \(http.statusCode) \(errorCode)")
        #endif
        switch http.statusCode {
        case 200...299: return data
        case 401: throw LooxLinkAPIError.unauthorized
        case 404: throw LooxLinkAPIError.notFound
        case 413: throw LooxLinkAPIError.payloadTooLarge
        case 410, 503:
            // Same frozen capability contract as the relay worker.
            if case .capability(let mode, let retryAfter)? =
                RelayAPIClient.capabilitySignal(from: http, data: data) {
                throw LooxLinkAPIError.capability(mode, retryAfter: retryAfter)
            }
            fallthrough   // plain 503 = infrastructure → generic server error
        default:
            let code = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw LooxLinkAPIError.server(status: http.statusCode, code: code)
        }
    }

    private func decodeOrThrow<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw LooxLinkAPIError.invalidResponse }
    }
}

/// Minimal JSON value wrapper so the create body can carry an explicit `null`
/// (Encodable dictionaries drop `nil` values, but the contract sends the key).
nonisolated enum AnyEncodableValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
