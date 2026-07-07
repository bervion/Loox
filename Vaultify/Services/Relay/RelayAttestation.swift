import CryptoKit
import DeviceCheck
import Foundation

/// App Attest admission for the relay control plane (INV-R02). Proves "this
/// request came from a genuine Loox app instance" — a layer distinct from the
/// Relay Principal signature (logical authorization) and from backend replay
/// control (nonce + sign_count CAS).
///
/// Two differences from `LooxLinkAttestation`:
///  1. Registration is per-backend — loox-relay keeps its own attested-key trust
///     state, so the device key is registered against loox-relay separately
///     (relay-namespaced keychain accounts).
///  2. The assertion binds the relay COMMAND transcript directly
///     (`clientDataHash = SHA256(LOOX-RELAY-AUTHZ-V1 bytes)`); there is NO
///     per-command challenge — the relay challenge is consumed only at register,
///     and command freshness is the existing nonce + server sign_count CAS.
///
/// Key lifecycle mirrors loox-link: generateKey → persist keyId immediately →
/// attest once (register) → assert per command. An invalid-key failure
/// (reinstall/restore/env change) resets to a fresh key + re-register, budgeted
/// to a single retry — never an endless generate→attest loop.
nonisolated enum RelayAttestation {
    // `-v2`: a one-time clean-slate key reset done during go-live triage. The
    // client crypto here was correct all along — the real cause of the early
    // assertion_signature_invalid was a server-side verifier bug (it verified
    // ECDSA over authData‖clientDataHash instead of Apple's actual
    // ECDSA-SHA256(authData‖clientDataHash) nonce). The reset is harmless and
    // left every device on a single freshly-registered key, so it stays.
    private static let keyIdAccount = "loox-relay-app-attest-key-id-v2"
    private static let registeredAccount = "loox-relay-app-attest-registered-v2"

    struct Assertion { let keyId: String; let assertionB64: String }

    static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    /// Assertion binding one relay command. `transcript` is the canonical
    /// `LOOX-RELAY-AUTHZ-V1` bytes the principal signature also covers, so the
    /// assertion and the signature bind the exact same command.
    static func assertion(forCommandTranscript transcript: Data,
                          baseURL: URL) async throws -> Assertion {
        do {
            return try await assertOnce(transcript: transcript, baseURL: baseURL)
        } catch let error as DCError where error.code == .invalidKey {
            // Reinstall/restore/env-mismatch: the stored key is dead. One fresh
            // key + re-register, then one more attempt — that's the budget.
            resetKey()
            return try await assertOnce(transcript: transcript, baseURL: baseURL)
        }
    }

    private static func assertOnce(transcript: Data, baseURL: URL) async throws -> Assertion {
        let keyId = try await registeredKeyId(baseURL: baseURL)
        let clientDataHash = Data(SHA256.hash(data: transcript))
        let assertion = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
        return Assertion(keyId: keyId, assertionB64: assertion.base64EncodedString())
    }

    /// Key id of a key loox-relay has verified — registering with loox-relay
    /// first if this device hasn't yet (separate trust state from loox-link).
    private static func registeredKeyId(baseURL: URL) async throws -> String {
        let keyId: String
        if let stored = try? KeychainStore.get(account: keyIdAccount),
           let s = String(data: stored, encoding: .utf8) {
            keyId = s
        } else {
            keyId = try await DCAppAttestService.shared.generateKey()
            // Persist before anything else can fail — the key is unreachable
            // without its id.
            try KeychainStore.set(Data(keyId.utf8), account: keyIdAccount)
        }
        if (try? KeychainStore.get(account: registeredAccount)) == nil {
            do {
                try await register(keyId: keyId, baseURL: baseURL)
            } catch {
                // A key can be attested with Apple only ONCE. If register's
                // attestKey succeeded but the POST failed (network blip / transient
                // 4xx), retrying would call attestKey on the same key and fail
                // forever. Drop the key so the next attempt starts from a fresh
                // generateKey instead of re-attesting a burned one.
                resetKey()
                throw error
            }
            try KeychainStore.set(Data([1]), account: registeredAccount)
        }
        return keyId
    }

    /// Register with loox-relay: clientDataHash = SHA256(raw challenge bytes),
    /// the challenge decoded from base64url (frozen contract, matches
    /// `register.ts`).
    private static func register(keyId: String, baseURL: URL) async throws {
        let challenge = try await RelayAPIClient.attestChallenge(baseURL: baseURL)
        guard let rawChallenge = base64urlDecode(challenge.challenge) else {
            throw RelayAPIClient.Failure.server(0)
        }
        let clientDataHash = Data(SHA256.hash(data: rawChallenge))
        let attestation = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
        try await RelayAPIClient.registerAttestation(
            attestationObjectB64: attestation.base64EncodedString(),
            challengeId: challenge.challengeId, keyId: keyId, baseURL: baseURL)
    }

    private static func resetKey() {
        KeychainStore.delete(account: keyIdAccount)
        KeychainStore.delete(account: registeredAccount)
    }

    private static func base64urlDecode(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t.append("=") }
        return Data(base64Encoded: t)
    }
}
