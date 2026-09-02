import CryptoKit
import DeviceCheck
import Foundation

/// App Attest gate for create-share. Proves "this request came from a genuine
/// Loox app instance" — it is NOT a user identity. Fail-closed: any
/// attest/assert failure surfaces an error; there is no fallback to an
/// unauthenticated create (C6).
///
/// Key lifecycle: generateKey → persist keyId IMMEDIATELY (a key without its
/// id is unusable) → attest once (register) → assert per create-share.
/// An invalid-key failure (reinstall/restore/environment change) regenerates
/// a fresh key and re-attests, with a budget of one retry per call — never an
/// endless generate→attest loop.
nonisolated enum LooxLinkAttestation {
    /// Scoped to the backend host: the server resolves attested keys per deploy
    /// environment, so staging state must never be offered to production.
    private static let keyStore = AppAttestKeyStore(
        namespace: "loox-link", apiBase: LooxLinkConfig.apiBase,
        legacyAccounts: ["loox-link-app-attest-key-id", "loox-link-app-attest-registered"])

    /// The persisted App Attest key id (the exact `X-Loox-App-Attest-Key-Id`
    /// header string) — read by the entitlement attach flow to request the
    /// `attest_key_link` binding. nil until a key has been minted.
    static var storedKeyId: String? { keyStore.storedKeyId }

    static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    /// Full assertion flow for one create-share request: ensure a registered
    /// key, fetch a single-use challenge, bind the request via the canonical
    /// hash, and sign it. Returns the headers the Worker verifies.
    static func assertCreateShare(api: LooxLinkAPIClient, ciphertext: Data, iv: Data,
                                  expiresInSeconds: UInt64, oneTime: Bool) async throws
        -> LooxLinkAPIClient.AssertionHeaders {
        do {
            return try await assertOnce(api: api, ciphertext: ciphertext, iv: iv,
                                        expiresInSeconds: expiresInSeconds, oneTime: oneTime)
        } catch let error as DCError where appAttestKeyIsDead(error) {
            // Reinstall/restore/env-mismatch: the stored key is dead. One
            // fresh key + re-register, then one more attempt — that's the budget.
            resetKey()
            return try await assertOnce(api: api, ciphertext: ciphertext, iv: iv,
                                        expiresInSeconds: expiresInSeconds, oneTime: oneTime)
        }
    }

    private static func assertOnce(api: LooxLinkAPIClient, ciphertext: Data, iv: Data,
                                   expiresInSeconds: UInt64, oneTime: Bool) async throws
        -> LooxLinkAPIClient.AssertionHeaders {
        let keyId = try await registeredKeyId(api: api)
        let challenge = try await api.getChallenge()
        let hash = LooxLinkCanonical.requestHash(
            challengeId: challenge.challengeId,
            ciphertext: ciphertext, iv: iv,
            cryptoVersion: LooxLinkConfig.cryptoVersion,
            expiresInSeconds: expiresInSeconds, envelope: nil, oneTime: oneTime)
        let assertion = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hash)
        return .init(challengeId: challenge.challengeId, keyId: keyId,
                     assertionB64: assertion.base64EncodedString())
    }

    /// Assertion for one shorten request (`LOOX-APP-ATTEST-SHORTEN-LINK-V1`).
    /// Same key/challenge machinery as create-share, its own binding; the
    /// server CONSUMES the challenge on a successful verify, so every attempt
    /// fetches a fresh one.
    static func assertShortenLink(api: LooxLinkAPIClient, shareId: String,
                                  shortenToken: String) async throws
        -> LooxLinkAPIClient.AssertionHeaders {
        do {
            return try await assertShortenOnce(api: api, shareId: shareId, shortenToken: shortenToken)
        } catch let error as DCError where appAttestKeyIsDead(error) {
            resetKey()
            return try await assertShortenOnce(api: api, shareId: shareId, shortenToken: shortenToken)
        }
    }

    private static func assertShortenOnce(api: LooxLinkAPIClient, shareId: String,
                                          shortenToken: String) async throws
        -> LooxLinkAPIClient.AssertionHeaders {
        let keyId = try await registeredKeyId(api: api)
        let challenge = try await api.getChallenge()
        let hash = LooxLinkCanonical.shortenRequestHash(
            challengeId: challenge.challengeId, shareId: shareId, shortenToken: shortenToken)
        let assertion = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hash)
        return .init(challengeId: challenge.challengeId, keyId: keyId,
                     assertionB64: assertion.base64EncodedString())
    }

    /// Key id of a key the server has verified — registering first if needed.
    private static func registeredKeyId(api: LooxLinkAPIClient) async throws -> String {
        let keyId: String
        if let stored = keyStore.storedKeyId {
            keyId = stored
        } else {
            keyStore.purgeLegacy()
            keyId = try await DCAppAttestService.shared.generateKey()
            try keyStore.persist(keyId: keyId)
        }
        // The marker must name THIS key. A reinstall destroys the Enclave key
        // but not the Keychain, so a bare "registered" flag would skip
        // registration and sign every assertion with a key the server has
        // never seen — the failure has no recovery path server-side.
        if !keyStore.isRegistered(keyId: keyId) {
            do {
                try await register(api: api, keyId: keyId)
            } catch {
                // A key can be attested with Apple only ONCE — a register that
                // fails after attestKey burns the key, so retrying re-attests it
                // and fails forever. Drop it and start fresh next time.
                resetKey()
                throw error
            }
            try keyStore.markRegistered(keyId: keyId)
        }
        return keyId
    }

    /// Register: clientDataHash = SHA256(base64urlDecode(challenge)) — the RAW
    /// challenge bytes, not a hash of the base64 string (frozen contract).
    private static func register(api: LooxLinkAPIClient, keyId: String) async throws {
        let challenge = try await api.getChallenge()
        guard let rawChallenge = LooxLinkCrypto.base64urlDecode(challenge.challenge) else {
            throw LooxLinkAPIError.invalidResponse
        }
        let clientDataHash = Data(SHA256.hash(data: rawChallenge))
        let attestation = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
        try await api.register(attestationObjectB64: attestation.base64EncodedString(),
                               challengeId: challenge.challengeId, keyId: keyId)
    }

    private static func resetKey() { keyStore.reset() }
}
