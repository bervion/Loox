import CryptoKit
import XCTest
@testable import Vaultify

/// Signed capability manifest: verification (signature/key set/schema/
/// timestamps), anti-rollback, cache-then-apply, and fail-safe dormancy while
/// the trusted key set is empty (BE B3 not frozen).
@MainActor
final class CapabilityManifestTests: XCTestCase {

    private let signingKey = P256.Signing.PrivateKey()
    private var trustedKeys: [String: Data] { ["k1": signingKey.publicKey.x963Representation] }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func envelope(version: UInt64 = 1,
                          schema: Int = 1,
                          issuedOffset: TimeInterval = -60,
                          expiresOffset: TimeInterval = 3600,
                          keyID: String = "k1",
                          privateEmail: String = "maintenance",
                          tamper: Bool = false) throws -> Data {
        let payload: [String: Any] = [
            "schema_version": schema,
            "manifest_version": version,
            "issued_at_unix_ms": Int64((now.timeIntervalSince1970 + issuedOffset) * 1000),
            "expires_at_unix_ms": Int64((now.timeIntervalSince1970 + expiresOffset) * 1000),
            "capabilities": [
                "private_email": ["mode": privateEmail, "retry_after": 900],
                "share_link": ["mode": "active"],
                "future_thing": ["mode": "active"],   // unknown key → ignored
            ],
        ]
        var payloadData = try JSONSerialization.data(withJSONObject: payload)
        let signature = try signingKey.signature(for: payloadData).rawRepresentation
        if tamper { payloadData[0] ^= 0xFF }
        let wire: [String: String] = [
            "payload_b64": payloadData.base64EncodedString(),
            "signature_b64": signature.base64EncodedString(),
            "key_id": keyID,
        ]
        return try JSONSerialization.data(withJSONObject: wire)
    }

    // MARK: Verifier

    func testVerifiesAndDecodesKnownCapabilities() throws {
        let manifest = try CapabilityManifestVerifier.verify(
            envelopeData: try envelope(), trustedKeys: trustedKeys, now: now, highestAcceptedVersion: 0)
        XCTAssertEqual(manifest.entry(for: .privateEmail)?.mode, .maintenance)
        XCTAssertEqual(manifest.entry(for: .privateEmail)?.retryAfter, 900)
        XCTAssertEqual(manifest.entry(for: .shareLink)?.mode, .active)
    }

    func testRejectsTamperUnknownKeyExpiryAndSchema() throws {
        func expectError(_ data: Data, _ expected: CapabilityManifestVerifier.VerifyError,
                         highest: UInt64 = 0) {
            XCTAssertThrowsError(try CapabilityManifestVerifier.verify(
                envelopeData: data, trustedKeys: trustedKeys, now: now,
                highestAcceptedVersion: highest)) { error in
                XCTAssertEqual(error as? CapabilityManifestVerifier.VerifyError, expected)
            }
        }
        expectError(try envelope(tamper: true), .badSignature)
        expectError(try envelope(keyID: "k9"), .unknownKey("k9"))
        expectError(try envelope(expiresOffset: -1), .expired)
        expectError(try envelope(issuedOffset: 60), .notYetValid)
        expectError(try envelope(schema: 2), .unsupportedSchema(2))
        expectError(try envelope(version: 3), .rollback(received: 3, highestAccepted: 7), highest: 7)
    }

    // MARK: Client (anti-rollback persistence + fail-safe dormancy)

    private func makeClient(keys: [String: Data]) -> (CapabilityManifestClient, CapabilityStore, UserDefaults) {
        let suite = "manifest-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = CapabilityStore(reachability: NetworkReachabilityMonitor(), defaults: defaults)
        return (CapabilityManifestClient(store: store, trustedKeys: keys, defaults: defaults), store, defaults)
    }

    func testAcceptAppliesPolicyAndBlocksRollback() throws {
        let (client, store, _) = makeClient(keys: trustedKeys)
        XCTAssertTrue(client.accept(envelopeData: try envelope(version: 5), now: now))
        XCTAssertEqual(store.modes[.privateEmail], .maintenance)
        XCTAssertEqual(client.highestAcceptedVersion, 5)
        // Manifest is policy distribution — health/breaker untouched.
        XCTAssertEqual(store.health[.privateEmail], .unknown)
        // Older version rejected, state unchanged.
        XCTAssertFalse(client.accept(envelopeData: try envelope(version: 4, privateEmail: "active"), now: now))
        XCTAssertEqual(store.modes[.privateEmail], .maintenance)
        XCTAssertEqual(client.highestAcceptedVersion, 5)
    }

    func testEmptyTrustedKeySetIsDormantFailSafe() throws {
        // Until BE freezes B3 the bundled key set is empty: nothing verifies,
        // nothing applies — the app keeps bundled defaults (all-active).
        let (client, store, _) = makeClient(keys: [:])
        XCTAssertFalse(client.accept(envelopeData: try envelope(), now: now))
        XCTAssertEqual(store.modes[.privateEmail], .active)
        XCTAssertTrue(CapabilityManifestVerifier.bundledTrustedKeys.isEmpty)
    }
}
