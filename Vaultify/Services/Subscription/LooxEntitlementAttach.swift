import Foundation
import CryptoKit

/// Client side of the Loox Entitlement attach contract (BE handoff 260716,
/// `X-Loox-Entitlement-Contract: 1`). Everything here is DORMANT plumbing for
/// B3: the backend runs `ENTITLEMENT_MODE=off`, purchases stay dark for App
/// Store users, and no UI consumes these results yet.
nonisolated enum LooxEntitlementConfig {
    /// Worker per build, mirroring `LooxLinkConfig`: dev talks to staging
    /// (Sandbox data lives there), Release talks to production — TestFlight's
    /// Sandbox JWS on prod is handled server-side (env matrix in the handoff;
    /// the app never declares an environment itself).
    #if DEBUG
    static let baseURL = URL(string: "https://entitlement-staging.looxpassword.com")!
    #else
    static let baseURL = URL(string: "https://entitlement.looxpassword.com")!
    #endif
    static let attachPath = "/v1/entitlement/attach"
    /// Coverage-telemetry header on create mutations (handoff §6.6) — how the
    /// backend measures client-capable coverage for the B3→B5 gate.
    static let contractHeader = "X-Loox-Entitlement-Contract"
    static let contractVersion = "1"
}

/// SHA-256 hex (lowercase) of the UTF-8 of a canonical identity string —
/// pinned byte-for-byte against the backend's frozen parity vectors
/// (`LooxEntitlementHashTests`). No trimming, no case folding, no
/// decode-then-hash: relay hashes the STANDARD-base64-with-padding principal
/// id (exactly what `RelayAPIClient` already sends as `principal_id`);
/// link/quick-view hash the `X-Loox-App-Attest-Key-Id` header string as sent.
nonisolated enum LooxBindingHash {
    static func hex(_ canonical: String) -> String {
        SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// One requested identity binding in an attach call.
nonisolated struct LooxAttachBindingRequest: Encodable, Sendable {
    let service: String          // "relay" | "link" | "quickview"
    let bindingType: String      // "relay_principal" | "attest_key_link" | "attest_key_qv"
    let bindingValueHash: String
    /// Link/QV key rotation only — relay principals never replace via billing.
    var replaceBindingId: Int? = nil

    enum CodingKeys: String, CodingKey {
        case service
        case bindingType = "binding_type"
        case bindingValueHash = "binding_value_hash"
        case replaceBindingId = "replace_binding_id"
    }
}

/// Per-service authorization returned by attach: a one-shot `grant` when the
/// binding still has to be made, plus a reusable `lease` for paid mutations.
nonisolated struct LooxAttachAuthorization: Decodable, Sendable {
    let service: String
    let bindingType: String
    let bindingRequired: Bool?
    let grant: String?
    let lease: String?
    let leaseExpiresAtMs: Int64?
    /// e.g. "binding_conflict" — the hash belongs to another account; never
    /// auto-steal, surface the support flow (B4 UI).
    let error: String?

    enum CodingKeys: String, CodingKey {
        case service
        case bindingType = "binding_type"
        case bindingRequired = "binding_required"
        case grant, lease
        case leaseExpiresAtMs = "lease_expires_at_ms"
        case error
    }
}

nonisolated struct LooxAttachResponse: Decodable, Sendable {
    let tier: String
    let status: String
    let expiresAtMs: Int64?
    let environment: String      // "Sandbox" | "Production" (server-derived)
    let authorizations: [LooxAttachAuthorization]

    enum CodingKeys: String, CodingKey {
        case tier, status
        case expiresAtMs = "expires_at_ms"
        case environment, authorizations
    }
}

nonisolated enum LooxAttachError: Error, Equatable {
    /// 422 — the JWS carries no appAccountToken; a token-setting bug, not retryable.
    case tokenMissing
    case unknownProduct
    /// 401 — permanent; never retry.
    case verificationFailed
    /// 503 apple_unavailable / service_unavailable — retry with backoff.
    case retryable
    /// 409 — defensive backend branch; retry like 503, and if it RECURS it is
    /// a backend bug to report, not something to retry forever (handoff §4).
    case noSubscriptionState
    case transport
    case server(Int)
}

/// Bare attach POST — single-flighting, backoff and state live in
/// `LooxEntitlementCoordinator`; this only speaks the wire contract.
nonisolated enum LooxEntitlementAttachClient {
    static func attach(transactionJWS: String,
                       bindings: [LooxAttachBindingRequest]) async throws -> LooxAttachResponse {
        var request = URLRequest(url: LooxEntitlementConfig.baseURL
            .appending(path: LooxEntitlementConfig.attachPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(LooxEntitlementConfig.contractVersion,
                         forHTTPHeaderField: LooxEntitlementConfig.contractHeader)

        struct Body: Encodable {
            let transactionJws: String
            let requestedBindings: [LooxAttachBindingRequest]
            enum CodingKeys: String, CodingKey {
                case transactionJws = "transaction_jws"
                case requestedBindings = "requested_bindings"
            }
        }
        request.httpBody = try JSONEncoder().encode(
            Body(transactionJws: transactionJWS, requestedBindings: bindings))

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw LooxAttachError.transport }
        guard let http = response as? HTTPURLResponse else { throw LooxAttachError.transport }

        switch http.statusCode {
        case 200...299:
            do { return try JSONDecoder().decode(LooxAttachResponse.self, from: data) }
            catch { throw LooxAttachError.server(http.statusCode) }
        case 401:
            throw LooxAttachError.verificationFailed
        case 409:
            throw LooxAttachError.noSubscriptionState
        case 422:
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0?["error"] as? String } ?? ""
            throw code == "token_missing" ? LooxAttachError.tokenMissing : LooxAttachError.unknownProduct
        case 503:
            throw LooxAttachError.retryable
        default:
            throw LooxAttachError.server(http.statusCode)
        }
    }
}
