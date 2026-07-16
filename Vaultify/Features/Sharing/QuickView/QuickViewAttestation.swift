import CryptoKit
import DeviceCheck
import Foundation

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
    private static let keyIdAccount = "quick-view-app-attest-key-id"

    /// The persisted App Attest key id (the exact `X-Loox-App-Attest-Key-Id`
    /// header string) — read by the entitlement attach flow to request the
    /// `attest_key_qv` binding. nil until a key has been minted.
    static var storedKeyId: String? {
        guard let data = try? KeychainStore.get(account: keyIdAccount) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static let registeredAccount = "quick-view-app-attest-registered"

    static var isSupported: Bool { DCAppAttestService.shared.isSupported }

    /// Assertion for one upload — binds the EXACT upload body via
    /// `LOOX-APP-ATTEST-QUICK-VIEW-V1`. `sessionID` is the wire hex string
    /// (used for the URL path); the transcript itself binds the hex-DECODED
    /// bytes (`sessionIDBytes`), per the frozen contract.
    static func assertUpload(api: QuickViewAPIClient, sessionID: String, sessionIDBytes: Data,
                             uploadBody: Data) async -> QuickViewAPIClient.AssertionHeaders? {
        guard isSupported else { return nil }
        do {
            return try await assertUploadOnce(api: api, sessionID: sessionID,
                                              sessionIDBytes: sessionIDBytes, uploadBody: uploadBody)
        } catch let error as DCError where error.code == .invalidKey {
            resetKey()
            return try? await assertUploadOnce(api: api, sessionID: sessionID,
                                               sessionIDBytes: sessionIDBytes, uploadBody: uploadBody)
        } catch {
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
        guard isSupported,
              let keyId = try? await registeredKeyId(api: api),
              let challenge = try? await api.getChallenge() else { return nil }
        let hash = Data(SHA256.hash(data: Data("\(challenge.challengeId)|\(sessionID)".utf8)))
        guard let assertion = try? await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: hash)
        else { return nil }
        return .init(challengeId: challenge.challengeId, keyId: keyId,
                     assertionB64: assertion.base64EncodedString())
    }

    /// Key id of a key the server has verified — registering first if needed.
    private static func registeredKeyId(api: QuickViewAPIClient) async throws -> String {
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
                try await register(api: api, keyId: keyId)
            } catch {
                // A key can be attested with Apple only ONCE — retrying a
                // failed register would re-attest a burned key and fail
                // forever. Drop it and start fresh next time.
                resetKey()
                throw error
            }
            try KeychainStore.set(Data([1]), account: registeredAccount)
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

    private static func resetKey() {
        KeychainStore.delete(account: keyIdAccount)
        KeychainStore.delete(account: registeredAccount)
    }
}
