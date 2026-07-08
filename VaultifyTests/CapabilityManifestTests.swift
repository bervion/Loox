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

    // MARK: Frozen parity vectors (byte-for-byte, per BE handoff §5)

    /// The fixture is a named-vector array (schema 1 "baseline" + "additive
    /// quick_view", schema 2 "schema2 exposure ...") — each entry independently
    /// asserted byte-for-byte against its own `canonical_bytes_hex`.
    private func loadVectors() throws -> [(name: String, manifest: CapabilityManifest, canonicalHex: String)] {
        let url = Bundle(for: Self.self).url(forResource: "cap-manifest-vectors-v1", withExtension: "json")!
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let vectors = root["vectors"] as! [[String: Any]]
        return try vectors.map { vector in
            let manifestData = try JSONSerialization.data(withJSONObject: vector["manifest"]!)
            let manifest = try JSONDecoder().decode(CapabilityManifest.self, from: manifestData)
            return (vector["name"] as! String, manifest, vector["canonical_bytes_hex"] as! String)
        }
    }

    private func vector(named name: String, in vectors: [(name: String, manifest: CapabilityManifest, canonicalHex: String)]) -> (name: String, manifest: CapabilityManifest, canonicalHex: String) {
        vectors.first { $0.name == name }!
    }

    /// Schema-1 vectors ("baseline", "additive quick_view") must stay
    /// byte-identical — the schema-2 `exposure` guard is additive-only and
    /// must never perturb pre-existing transcripts.
    func testSchema1VectorsTranscriptUnchanged() throws {
        let vectors = try loadVectors()
        for name in ["baseline (private_email + share_link)",
                     "additive quick_view (private_email + share_link + quick_view)"] {
            let v = vector(named: name, in: vectors)
            XCTAssertEqual(v.manifest.schemaVersion, 1)
            let hex = v.manifest.transcript.map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hex, v.canonicalHex, "schema-1 vector '\(name)' drifted from the frozen BE vector")
        }
    }

    /// Schema-2 vector: `exposure` encodes as a plain string appended after
    /// `optString(message_key)` for every capability, byte-for-byte against
    /// the BE oracle.
    func testSchema2ExposureVectorTranscriptMatchesFrozenByteForByte() throws {
        let vectors = try loadVectors()
        let v = vector(named: "schema2 exposure (quick_view=beta, others=ga)", in: vectors)
        XCTAssertEqual(v.manifest.schemaVersion, 2)
        let hex = v.manifest.transcript.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, v.canonicalHex, "schema-2 exposure transcript drifted from the frozen BE vector")
        XCTAssertEqual(v.manifest.exposure(for: .quickView), "beta")
        XCTAssertEqual(v.manifest.exposure(for: .privateEmail), "ga")
        XCTAssertEqual(v.manifest.exposure(for: .shareLink), "ga")
    }

    /// A schema-1 manifest (or a schema-2 entry omitting the field) parses
    /// `exposure` as nil — callers must not coerce that into a signed "ga".
    func testExposureNilWhenAbsentOrSchema1() throws {
        let vectors = try loadVectors()
        let baseline = vector(named: "baseline (private_email + share_link)", in: vectors)
        XCTAssertNil(baseline.manifest.exposure(for: .privateEmail))
        XCTAssertNil(baseline.manifest.exposure(for: .shareLink))
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
        // Anti-rollback: a STRICTLY older version is rejected (a replayed older
        // manifest must never re-enable a capability a newer one retired)...
        XCTAssertThrowsError(try CapabilityManifestVerifier.verify(
            manifestData: data, trustedKeys: testKeys, now: now, highestAcceptedVersion: 43)) {
            XCTAssertEqual($0 as? CapabilityManifestVerifier.VerifyError,
                           .rollback(received: 42, highestAccepted: 43))
        }
        // ...but an EQUAL version is NOT a rollback — it is an idempotent re-serve
        // of the current document, admitted so the client store can run its
        // hash-gated recovery (the client decides recovery vs monotonic advance).
        XCTAssertNoThrow(try CapabilityManifestVerifier.verify(
            manifestData: data, trustedKeys: testKeys, now: now, highestAcceptedVersion: 42))
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
        let bytes = CapabilityManifestVerifier.bundledTrustedKeys["cap-2026-02"]
        XCTAssertNotNil(bytes)
        XCTAssertNotNil(try? P256.Signing.PublicKey(x963Representation: bytes!))
        // Fingerprint from the BE handoff (rotated 260708).
        let fingerprint = SHA256.hash(data: bytes!).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(fingerprint, "a4752c4323ce69cd66ca85efc5b772c8cd1b923f6c823affeef0fbc01b5f99f4")
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
        // Equal-version re-serve is an idempotent recovery (same canonical
        // transcript → hash matches): accepted, high-water neither advanced nor
        // lowered. (The signature bytes differ per call; the transcript does not.)
        XCTAssertTrue(client.accept(manifestData: try signed(sampleManifest()), now: now))
        XCTAssertEqual(client.highestAcceptedVersion, 42)
        defaults.removePersistentDomain(forName: suite)
    }

    func testUnknownMessageKeyNeverRendersRaw() {
        XCTAssertNil(CapabilityMessageKey.localized("totally_unknown_key"))
        XCTAssertNil(CapabilityMessageKey.localized(nil))
        XCTAssertNotNil(CapabilityMessageKey.localized("private_email_maintenance"))
        XCTAssertNotNil(CapabilityMessageKey.localized("private_email_shutdown_notice"))
    }
}
