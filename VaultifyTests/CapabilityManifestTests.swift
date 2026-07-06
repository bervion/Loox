import CryptoKit
import XCTest
@testable import Vaultify

/// LOOX-CAP-MANIFEST-V1: frozen byte parity against the BE vector, signature
/// verification over the canonical transcript, strict anti-rollback, trusted
/// key pinning, and manifest → store application (policy + per-op narrowing).
@MainActor
final class CapabilityManifestTests: XCTestCase {

    private let signingKey = P256.Signing.PrivateKey()
    private var testKeys: [String: Data] { ["cap-test": signingKey.publicKey.x963Representation] }
    private let now = Date(timeIntervalSince1970: 1_783_330_000)

    // MARK: Frozen parity vector (byte-for-byte, per BE handoff §5)

    private func loadVector() throws -> (manifest: CapabilityManifest, canonicalHex: String) {
        let url = Bundle(for: Self.self).url(forResource: "cap-manifest-vectors-v1", withExtension: "json")!
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let manifestData = try JSONSerialization.data(withJSONObject: root["manifest"]!)
        let manifest = try JSONDecoder().decode(CapabilityManifest.self, from: manifestData)
        return (manifest, root["canonical_bytes_hex"] as! String)
    }

    func testTranscriptMatchesFrozenVectorByteForByte() throws {
        let (manifest, expectedHex) = try loadVector()
        let hex = manifest.transcript.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, expectedHex, "canonical transcript drifted from the frozen BE vector")
    }

    // MARK: Signature + freshness + rollback

    /// Encode `manifest` (with `keyID`), sign its transcript, emit wire JSON.
    /// `tamper` mutates a covered field AFTER signing.
    private func signed(_ manifest: CapabilityManifest, keyID: String = "cap-test",
                        tamper: Bool = false) throws -> Data {
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(manifest)) as! [String: Any]
        dict["key_id"] = keyID
        let unsigned = try JSONDecoder().decode(
            CapabilityManifest.self, from: JSONSerialization.data(withJSONObject: dict))
        let signature = try signingKey.signature(for: unsigned.transcript).rawRepresentation
        dict["signature"] = signature.base64EncodedString()
        if tamper { dict["manifest_version"] = (dict["manifest_version"] as! NSNumber).uint64Value + 1 }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private func sampleManifest(version: UInt64 = 42, expiresOffset: TimeInterval = 3600) -> CapabilityManifest {
        CapabilityManifest(
            schemaVersion: 1, manifestVersion: version, keyID: "cap-test",
            issuedAt: Int64((now.timeIntervalSince1970 - 60) * 1000),
            expiresAt: Int64((now.timeIntervalSince1970 + expiresOffset) * 1000),
            capabilities: [
                "private_email": .init(policy: .maintenance,
                                       operations: ["create": "disabled", "read": "enabled"],
                                       messageKey: "private_email_maintenance"),
                "share_link": .init(policy: .enabled, operations: ["create": "enabled"], messageKey: nil),
            ],
            signature: nil)
    }

    func testVerifyAcceptsValidAndRejectsTamperedOrStrictRollback() throws {
        let data = try signed(sampleManifest())
        let verified = try CapabilityManifestVerifier.verify(
            manifestData: data, trustedKeys: testKeys, now: now, highestAcceptedVersion: 41)
        XCTAssertEqual(verified.manifestVersion, 42)
        XCTAssertEqual(verified.entry(for: .privateEmail)?.policy, .maintenance)
        // Tampered field after signing → bad signature.
        XCTAssertThrowsError(try CapabilityManifestVerifier.verify(
            manifestData: try signed(sampleManifest(), tamper: true),
            trustedKeys: testKeys, now: now, highestAcceptedVersion: 0)) {
            XCTAssertEqual($0 as? CapabilityManifestVerifier.VerifyError, .badSignature)
        }
        // STRICT anti-rollback: equal version is rejected too (BE handoff:
        // reject ≤ highest — a replayed old manifest must never re-enable).
        XCTAssertThrowsError(try CapabilityManifestVerifier.verify(
            manifestData: data, trustedKeys: testKeys, now: now, highestAcceptedVersion: 42)) {
            XCTAssertEqual($0 as? CapabilityManifestVerifier.VerifyError,
                           .rollback(received: 42, highestAccepted: 42))
        }
        // Unknown key id → pinned-set rejection.
        XCTAssertThrowsError(try CapabilityManifestVerifier.verify(
            manifestData: try signed(sampleManifest(), keyID: "cap-9999"),
            trustedKeys: testKeys, now: now, highestAcceptedVersion: 0)) {
            XCTAssertEqual($0 as? CapabilityManifestVerifier.VerifyError, .unknownKey("cap-9999"))
        }
        // Expired → treated as no manifest.
        XCTAssertThrowsError(try CapabilityManifestVerifier.verify(
            manifestData: try signed(sampleManifest(expiresOffset: -1)),
            trustedKeys: testKeys, now: now, highestAcceptedVersion: 0)) {
            XCTAssertEqual($0 as? CapabilityManifestVerifier.VerifyError, .expired)
        }
    }

    func testBundledOperatorKeyPinsAndParses() {
        let bytes = CapabilityManifestVerifier.bundledTrustedKeys["cap-2026-01"]
        XCTAssertNotNil(bytes)
        XCTAssertNotNil(try? P256.Signing.PublicKey(x963Representation: bytes!))
        // Fingerprint from the BE handoff.
        let fingerprint = SHA256.hash(data: bytes!).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(fingerprint, "eee533bf2722e0f21f02e813f2934f29cb4991d24fc1a070f11aa635ba9a7da1")
    }

    // MARK: Client application (policy + per-operation narrowing + message key)

    func testAcceptAppliesPolicyOperationsAndMessageKey() throws {
        let suite = "manifest-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = CapabilityStore(reachability: NetworkReachabilityMonitor(), defaults: defaults)
        let client = CapabilityManifestClient(store: store, trustedKeys: testKeys, defaults: defaults)

        XCTAssertTrue(client.accept(manifestData: try signed(sampleManifest()), now: now))
        XCTAssertEqual(store.modes[.privateEmail], .maintenance)
        XCTAssertEqual(store.modes[.shareLink], .active)   // "enabled" bridges to .active
        XCTAssertEqual(store.messageKeys[.privateEmail], "private_email_maintenance")
        XCTAssertEqual(store.disabledOperations[.privateEmail], [.create])
        // Manifest is policy distribution — health/breakers untouched.
        XCTAssertEqual(store.health[.privateEmail], .unknown)
        XCTAssertEqual(client.highestAcceptedVersion, 42)
        // Equal-version replay rejected (strict), state unchanged.
        XCTAssertFalse(client.accept(manifestData: try signed(sampleManifest()), now: now))
        defaults.removePersistentDomain(forName: suite)
    }

    func testUnknownMessageKeyNeverRendersRaw() {
        XCTAssertNil(CapabilityMessageKey.localized("totally_unknown_key"))
        XCTAssertNil(CapabilityMessageKey.localized(nil))
        XCTAssertNotNil(CapabilityMessageKey.localized("private_email_maintenance"))
        XCTAssertNotNil(CapabilityMessageKey.localized("private_email_shutdown_notice"))
    }
}
