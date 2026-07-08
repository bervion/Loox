import Foundation

/// Errors surfaced by the Quick View session/mailbox API. Failure discipline
/// (backend proposal §B2): expired/consumed/unknown/claimed-by-someone-else
/// sessions are indistinguishable BY DESIGN on both sides — they all collapse
/// to `.sessionUnavailable`, never a state-specific message.
nonisolated enum QuickViewAPIError: Error, LocalizedError, Sendable {
    case invalidResponse
    case unauthorized
    case payloadTooLarge
    /// Expired / consumed / unknown / claimed-elsewhere — ALL collapse here.
    case sessionUnavailable
    case capability(CapabilityServiceMode, retryAfter: Int?)
    case server(status: Int, code: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: appString("The Quick View service sent an unexpected response.")
        case .unauthorized: appString("This app couldn't prove it's a genuine Loox install. Try again later.")
        case .payloadTooLarge: appString("This item is too large to open on a computer.")
        case .sessionUnavailable: appString("Start again on the computer.")
        case .capability(.maintenance, _): appString("Open on Computer is temporarily paused. Your vault continues to work normally.")
        case .capability(.retired, _): appString("Open on Computer is no longer offered. Your saved vault items are unchanged.")
        case .capability: appString("Open on Computer is temporarily unavailable. Your vault is not affected.")
        case .server(let status, let code): appString("Quick View service error (\(code ?? String(status))).")
        }
    }
}

/// Thin URLSession client for the dedicated `quick-view` Worker (backend
/// proposal §B2). The request body only ever carries ciphertext + the app's
/// ephemeral public key — the shared secret and any field plaintext never
/// appear in any request, header, or log.
nonisolated struct QuickViewAPIClient: Sendable {
    struct AssertionHeaders: Sendable {
        let challengeId: String
        let keyId: String
        let assertionB64: String
    }

    struct Challenge: Decodable, Sendable {
        let challengeId: String
        /// base64url raw challenge bytes; single-use, server-consumed on verify.
        let challenge: String
        enum CodingKeys: String, CodingKey { case challengeId = "challenge_id", challenge }
    }

    /// One resolved session: the raw signed-envelope JSON bytes (fed straight
    /// into `QuickViewSessionEnvelopeVerifier`) plus the browser's actual
    /// ephemeral public keys, which the QR/code carrier delivers alongside
    /// the envelope so the verifier can close the substitution gap a
    /// locator-only carrier would otherwise leave open (compares
    /// `SHA256(these keys)` against the envelope's own signed hashes).
    ///
    /// `/sessions/resolve` returns `signed_session_envelope` plus the browser's
    /// raw `browser_enc_pub` / `browser_sig_pub` (base64url) — the app needs the
    /// actual enc public key to run ECDH and to check it hashes to the envelope's
    /// signed `enc_key_hash`. Verified end-to-end against live staging.
    nonisolated struct ResolvedSession: Sendable {
        let envelopeData: Data
        let browserEncPublicKey: Data
        let browserSigPublicKey: Data
    }

    var baseURL: URL { QuickViewConfig.apiBase }
    private var servicePrefix: String { QuickViewConfig.servicePathPrefix }

    func getChallenge() async throws -> Challenge {
        let request = makeRequest(path: "\(servicePrefix)/attestation/challenges")
        let data = try await send(request)
        return try decodeOrThrow(Challenge.self, from: data)
    }

    /// Registers an App Attest key (idempotent per key). 2xx on success.
    func register(attestationObjectB64: String, challengeId: String, keyId: String) async throws {
        var request = makeRequest(path: "\(servicePrefix)/attestation/register")
        request.setValue(challengeId, forHTTPHeaderField: "X-Loox-Challenge-Id")
        request.setValue(keyId, forHTTPHeaderField: "X-Loox-App-Attest-Key-Id")
        request.httpBody = try JSONEncoder().encode(["attestation_object_b64": attestationObjectB64])
        _ = try await send(request)
    }

    /// `POST /sessions/resolve` — code in BODY, never a query string (backend
    /// §B2/P1-3: codes must never land in access logs/browser history).
    func resolve(code: String) async throws -> ResolvedSession {
        var request = makeRequest(path: "\(servicePrefix)/sessions/resolve")
        request.httpBody = try JSONEncoder().encode(["code": code])
        let data = try await send(request)
        // Backend response field is `signed_session_envelope`; every binary
        // value on the wire is base64url. NOTE: the app also needs the
        // browser's raw enc/sig public keys (for ECDH + the enc_key_hash
        // substitution guard) — resolve MUST carry `browser_enc_pub` /
        // `browser_sig_pub` (base64url). See BE follow-up if absent.
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let envelopeObject = body["signed_session_envelope"],
              let envelopeData = try? JSONSerialization.data(withJSONObject: envelopeObject),
              let encPubB64 = body["browser_enc_pub"] as? String,
              let sigPubB64 = body["browser_sig_pub"] as? String,
              let encPub = QuickViewWire.base64URLDecode(encPubB64),
              let sigPub = QuickViewWire.base64URLDecode(sigPubB64)
        else { throw QuickViewAPIError.invalidResponse }
        return ResolvedSession(envelopeData: envelopeData, browserEncPublicKey: encPub,
                               browserSigPublicKey: sigPub)
    }

    /// Advisory bind — telemetry/"phone connected" UI only. NEVER throws: a
    /// failure here must be structurally impossible to block approve.
    func bindAdvisory(sessionID: String, assertion: AssertionHeaders?) async {
        var request = makeRequest(path: "\(servicePrefix)/sessions/\(sessionID)/bind")
        applyAssertion(assertion, to: &request)
        _ = try? await send(request)
    }

    /// `POST /sessions/{id}/payload` — first valid upload atomically claims
    /// the session (backend §B1, CREATED→APPROVED). `ciphertext` is the
    /// FULL opaque wire blob (12-byte nonce ‖ AES-GCM ciphertext ‖ tag) — no
    /// separate `nonce` field on the wire (contract: the ciphertext is
    /// opaque to the server).
    func upload(sessionID: String, ciphertext: Data,
               appEphemeralPublicKey: Data, aad: Data,
               assertion: AssertionHeaders?) async throws {
        var request = makeRequest(path: QuickViewCanonical.uploadPath(sessionID: sessionID))
        applyAssertion(assertion, to: &request)
        // Backend `/payload` expects exactly three base64url fields (all wire
        // fields are base64url) and the AAD travels as a SINGLE opaque blob —
        // NOT decomposed into `enc_key_hash`/`approval_id`/… (the worker has a
        // tripwire that rejects a body exposing an un-encrypted key). `aad` is
        // the exact AAD byte string the sealer authenticated; `ciphertext` is
        // the opaque IV(12)‖ct‖tag.
        let body: [String: Any] = [
            "ciphertext": QuickViewWire.base64URLEncode(ciphertext),
            "app_eph_pub": QuickViewWire.base64URLEncode(appEphemeralPublicKey),
            "aad": QuickViewWire.base64URLEncode(aad),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        if let count = request.httpBody?.count, count > QuickViewConfig.maxBodyBytes {
            throw QuickViewAPIError.payloadTooLarge
        }
        _ = try await send(request)
    }

    // MARK: - Plumbing

    private func applyAssertion(_ assertion: AssertionHeaders?, to request: inout URLRequest) {
        guard let assertion else { return }
        request.setValue(assertion.challengeId, forHTTPHeaderField: "X-Loox-Challenge-Id")
        request.setValue(assertion.keyId, forHTTPHeaderField: "X-Loox-App-Attest-Key-Id")
        request.setValue(assertion.assertionB64, forHTTPHeaderField: "X-Loox-App-Attest-Assertion")
    }

    private func makeRequest(path: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw QuickViewAPIError.invalidResponse }
        #if DEBUG
        // Path + status only — never bodies, codes, or session ids.
        print("[QuickView] \(request.httpMethod ?? "?") \(request.url?.path ?? "?") → \(http.statusCode)")
        #endif
        // Verified operator state deserves a deliberate reply — classify
        // BEFORE the session/infra split (same discipline as LooxLink).
        if (400...599).contains(http.statusCode),
           case .capability(let mode, let retryAfter)? = RelayAPIClient.capabilitySignal(from: http, data: data) {
            throw QuickViewAPIError.capability(mode, retryAfter: retryAfter)
        }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw QuickViewAPIError.unauthorized
        case 404, 409, 410: throw QuickViewAPIError.sessionUnavailable
        case 413: throw QuickViewAPIError.payloadTooLarge
        default:
            let code = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw QuickViewAPIError.server(status: http.statusCode, code: code)
        }
    }

    private func decodeOrThrow<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw QuickViewAPIError.invalidResponse }
    }
}
