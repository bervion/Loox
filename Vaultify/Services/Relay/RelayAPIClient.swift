import Foundation

/// Thin HTTPS client for the relay control API. Every mutating call carries a
/// principal-signed canonical transcript (the ONLY auth today — App Attest for
/// relay is deliberately off until its contract + vectors are frozen; do not
/// send assertion headers here until then).
nonisolated enum RelayAPIClient {

    enum Failure: Error, Equatable {
        case unauthorized          // 401 — bad signature / unknown principal
        case nonceReplay           // 409 nonce_replay — retry with a fresh nonce
        case epochStale            // 409 epoch_stale — refresh principal state
        case aliasExists           // 409 alias_exists — regenerate the local-part
        case rateLimited           // 429 — back off (~30/min, 500/day per principal)
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

    /// POST/DELETE a signed command. Throws a mapped `Failure`.
    static func send(_ command: RelayCommand, signature: Data, genesisPublicKey: Data? = nil,
                     path: String, method: String = "POST",
                     baseURL: URL = RelayConfig.apiBaseURL) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body(for: command, signature: signature, genesisPublicKey: genesisPublicKey))

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw Failure.transport }

        guard let http = response as? HTTPURLResponse else { throw Failure.transport }
        switch http.statusCode {
        case 200...299: return
        case 401: throw Failure.unauthorized
        case 409: throw conflictFailure(from: data)
        case 429: throw Failure.rateLimited
        default: throw Failure.server(http.statusCode)
        }
    }

    private static func conflictFailure(from data: Data) -> Failure {
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            .flatMap { $0?["error"] as? String } ?? ""
        switch code {
        case "nonce_replay": return .nonceReplay
        case "epoch_stale": return .epochStale
        case "alias_exists": return .aliasExists
        default: return .server(409)
        }
    }
}
