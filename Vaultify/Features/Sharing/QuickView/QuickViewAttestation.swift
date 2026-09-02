import CryptoKit
import DeviceCheck
import Foundation
import OSLog

/// App Attest gate for Quick View uploads/binds — proves "this request came
/// from a genuine Loox app instance", never a user identity. Key lifecycle
/// mirrors `LooxLinkAttestation`: generateKey → persist keyId → attest once
/// (register) → assert per request, one invalid-key retry budget.
///
/// Shadow posture (`QuickViewConfig.assertionRequired == false`): every
/// method here returns `nil` instead of throwing on ANY failure — a broken
/// register/assert path must never block upload or bind while the server
/// hasn't moved to required mode. Once the ladder flips, the caller's own
/// fail-closed check (via `QuickViewConfig.assertionRequired`) is what
/// actually enforces — this type never grows an enforcement opinion of its
/// own, so the two can't drift.
nonisolated enum QuickViewAttestation {
    /// Scoped to the backend host: the server resolves attested keys per deploy
    /// environment, so staging state must never be offered to production.
    private static let keyStore = AppAttestKeyStore(
        namespace: "quick-view", apiBase: QuickViewConfig.apiBase,
        legacyAccounts: ["quick-view-app-attest-key-id", "quick-view-app-attest-registered"])
    /// Every nil-return below logs its reason — a silently degraded assertion
    /// once shipped a naked upload straight into the server's fail-closed 401
    /// with zero device-side evidence of which step died.
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vaultify",
                                       category: "quick-view-attest")

    /// Error domain + code + text, no user data — safe for `.public` logging.
    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain)#\(ns.code) \(ns.localizedDescription)"
    }

    /// The persisted App Attest key id (the exact `X-Loox-App-Attest-Key-Id`
    /// header string) — read by the entitlement attach flow to request the
    /// `attest_key_qv` binding. nil until a key has been minted.
    static var storedKeyId: String? { keyStore.storedKeyId }

    static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    /// Assertion for one upload — binds the EXACT upload body via
    /// `LOOX-APP-ATTEST-QUICK-VIEW-V1`. `sessionID` is the wire hex string
    /// (used for the URL path); the transcript itself binds the hex-DECODED
    /// bytes (`sessionIDBytes`), per the frozen contract.
    static func assertUpload(api: QuickViewAPIClient, sessionID: String, sessionIDBytes: Data,
                             uploadBody: Data) async -> QuickViewAPIClient.AssertionHeaders? {
        guard isSupported else {
            logger.warning("App Attest unsupported on this device, no upload assertion")
            return nil
        }
        do {
            return try await assertUploadOnce(api: api, sessionID: sessionID,
                                              sessionIDBytes: sessionIDBytes, uploadBody: uploadBody)
        } catch let error as DCError where appAttestKeyIsDead(error) {
            logger.warning("upload assertion key invalid, re-keying once")
            resetKey()
            do {
                return try await assertUploadOnce(api: api, sessionID: sessionID,
                                                  sessionIDBytes: sessionIDBytes, uploadBody: uploadBody)
            } catch {
                logger.error("re-keyed upload assertion failed: \(describe(error), privacy: .public)")
                return nil
            }
        } catch {
            logger.error("upload assertion failed: \(describe(error), privacy: .public)")
            return nil
        }
    }

    private static func assertUploadOnce(api: QuickViewAPIClient, sessionID: String, sessionIDBytes: Data,
                                         uploadBody: Data) async throws
        -> QuickViewAPIClient.AssertionHeaders {
        let keyId = try await registeredKeyId(api: api)
        let challenge = try await api.getChallenge()
        let path = QuickViewCanonical.uploadPath(sessionID: sessionID)
        let hash = QuickViewCanonical.assertionClientDataHash(
            path: path, challengeID: challenge.challengeId, sessionIDBytes: sessionIDBytes, uploadBody: uploadBody)
        let assertion = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hash)
        return .init(challengeId: challenge.challengeId, keyId: keyId,
                     assertionB64: assertion.base64EncodedString())
    }

    /// Advisory bind gets a shadow assertion too (cheap, phase-03) — bound
    /// only to the session id and challenge (there is no upload body yet at
    /// bind time). Never throws: bind is advisory and must never gate on
    /// attestation succeeding.
    static func assertBind(api: QuickViewAPIClient, sessionID: String) async
        -> QuickViewAPIClient.AssertionHeaders? {
        guard isSupported else { return nil }
        do {
            let keyId = try await registeredKeyId(api: api)
            let challenge = try await api.getChallenge()
            let hash = Data(SHA256.hash(data: Data("\(challenge.challengeId)|\(sessionID)".utf8)))
            let assertion = try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hash)
            return .init(challengeId: challenge.challengeId, keyId: keyId,
                         assertionB64: assertion.base64EncodedString())
        } catch {
            // Bind stays advisory (never gates approve) — but the skip reason
            // must be visible: bind failures foreshadow the upload assertion
            // failing the same way.
            logger.warning("bind assertion skipped: \(describe(error), privacy: .public)")
            return nil
        }
    }

    /// Key id of a key the server has verified — registering first if needed.
    private static func registeredKeyId(api: QuickViewAPIClient) async throws -> String {
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
                // A key can be attested with Apple only ONCE — retrying a
                // failed register would re-attest a burned key and fail
                // forever. Drop it and start fresh next time.
                logger.error("key register failed, dropping key: \(describe(error), privacy: .public)")
                resetKey()
                throw error
            }
            try keyStore.markRegistered(keyId: keyId)
        }
        return keyId
    }

    /// Register: clientDataHash = SHA256(base64urlDecode(challenge)) — the
    /// RAW challenge bytes, not a hash of the base64 string.
    private static func register(api: QuickViewAPIClient, keyId: String) async throws {
        let challenge = try await api.getChallenge()
        guard let rawChallenge = LooxLinkCrypto.base64urlDecode(challenge.challenge) else {
            throw QuickViewAPIError.invalidResponse
        }
        let clientDataHash = Data(SHA256.hash(data: rawChallenge))
        let attestation = try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
        try await api.register(attestationObjectB64: attestation.base64EncodedString(),
                               challengeId: challenge.challengeId, keyId: keyId)
    }

    private static func resetKey() { keyStore.reset() }
}
