import CryptoKit
import XCTest
@testable import Vaultify

/// Signed domain registry: transcript byte parity against the frozen vectors,
/// lenient post-verification mapping, and the verifier's env/rollback/tamper
/// gates (self-signed with a generated key so no fixture private key exists).
final class DomainRegistryDocumentTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Vector: Decodable {
            let name: String
            let registry: DomainRegistryDocument
            let canonical_bytes_hex: String
        }
        let vectors: [Vector]
    }

    private func loadVectors() throws -> [Fixture.Vector] {
        let bundle = Bundle(for: DomainRegistryDocumentTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "domain-registry-vectors-v1", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).vectors
    }

    func testTranscriptByteParityAgainstFrozenVectors() throws {
        let vectors = try loadVectors()
        XCTAssertEqual(vectors.count, 3)
        for vector in vectors {
            XCTAssertEqual(vector.registry.transcript.hexString, vector.canonical_bytes_hex,
                           "registry vector \(vector.name) drifted")
        }
    }

    func testLenientMappingIgnoresUnknownCapabilityAndFailsClosedOnLifecycle() throws {
        let document = try JSONDecoder().decode(DomainRegistryDocument.self, from: Data("""
        {"schema_version":1,"registry_version":1,"key_id":"k","env":"staging",
         "issued_at":0,"expires_at":1,
         "domains":[{"id":"d1","display_name":"D1","email_address_domain":"d1.example",
                     "short_link_host":null,
                     "capabilities":["email","holographic_mail"],
                     "lifecycle":"quantum","is_primary_email_choice":true,
                     "is_primary_short_link_choice":false}]}
        """.utf8))
        let descriptor = try XCTUnwrap(document.descriptors.first)
        XCTAssertEqual(descriptor.capabilities, [.privateEmail])   // unknown capability dropped
        XCTAssertEqual(descriptor.lifecycle, .createDisabled)      // unknown lifecycle → no new creation
    }

    // MARK: Verifier (self-signed)

    private func signedDocumentData(env: String = DomainRegistryClient.expectedEnv,
                                    registryVersion: UInt64 = 5,
                                    key: P256.Signing.PrivateKey,
                                    mutateAfterSigning: ((inout [String: Any]) -> Void)? = nil) throws -> Data {
        var json: [String: Any] = [
            "schema_version": 1, "registry_version": registryVersion, "key_id": "test-key",
            "env": env,
            "issued_at": 0, "expires_at": Int64.max,
            "domains": [[
                "id": "relay-main", "display_name": "relay.looxpassword.com",
                "email_address_domain": "relay.looxpassword.com", "short_link_host": nil,
                "capabilities": ["email"], "lifecycle": "active",
                "is_primary_email_choice": true, "is_primary_short_link_choice": false,
            ] as [String: Any?]].map { $0.compactMapValues { $0 } },
        ]
        let unsigned = try JSONSerialization.data(withJSONObject: json)
        let document = try JSONDecoder().decode(DomainRegistryDocument.self, from: unsigned)
        let signature = try key.signature(for: document.transcript)
        json["signature"] = signature.rawRepresentation.base64EncodedString()
        mutateAfterSigning?(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func trusted(_ key: P256.Signing.PrivateKey) -> [String: Data] {
        ["test-key": key.publicKey.x963Representation]
    }

    func testVerifierAcceptsSelfSignedDocument() throws {
        let key = P256.Signing.PrivateKey()
        let data = try signedDocumentData(key: key)
        let document = try DomainRegistryVerifier.verify(
            documentData: data, trustedKeys: trusted(key),
            expectedEnv: DomainRegistryClient.expectedEnv, now: .now, highestAcceptedVersion: 0)
        XCTAssertEqual(document.registryVersion, 5)
        XCTAssertEqual(document.descriptors.first?.emailAddressDomain, "relay.looxpassword.com")
    }

    func testVerifierRejectsWrongEnvironment() throws {
        let key = P256.Signing.PrivateKey()
        // Signed for the OTHER env — a valid signature must not cross envs.
        let other = DomainRegistryClient.expectedEnv == "staging" ? "production" : "staging"
        let data = try signedDocumentData(env: other, key: key)
        XCTAssertThrowsError(try DomainRegistryVerifier.verify(
            documentData: data, trustedKeys: trusted(key),
            expectedEnv: DomainRegistryClient.expectedEnv, now: .now, highestAcceptedVersion: 0)) {
            XCTAssertEqual($0 as? DomainRegistryVerifier.VerifyError, .wrongEnvironment(other))
        }
    }

    func testVerifierRejectsStrictlyOlderButAdmitsEqualVersion() throws {
        let key = P256.Signing.PrivateKey()
        let data = try signedDocumentData(registryVersion: 5, key: key)
        // Strictly older → rollback.
        XCTAssertThrowsError(try DomainRegistryVerifier.verify(
            documentData: data, trustedKeys: trusted(key),
            expectedEnv: DomainRegistryClient.expectedEnv, now: .now, highestAcceptedVersion: 6)) {
            XCTAssertEqual($0 as? DomainRegistryVerifier.VerifyError,
                           .rollback(received: 5, highestAccepted: 6))
        }
        // Equal version → admitted (idempotent re-serve for the client's recovery).
        XCTAssertNoThrow(try DomainRegistryVerifier.verify(
            documentData: data, trustedKeys: trusted(key),
            expectedEnv: DomainRegistryClient.expectedEnv, now: .now, highestAcceptedVersion: 5))
    }

    func testVerifierRejectsTamperedDomains() throws {
        let key = P256.Signing.PrivateKey()
        let data = try signedDocumentData(key: key) { json in
            var domains = json["domains"] as! [[String: Any]]
            domains[0]["email_address_domain"] = "evil.example"   // post-signature mutation
            json["domains"] = domains
        }
        XCTAssertThrowsError(try DomainRegistryVerifier.verify(
            documentData: data, trustedKeys: trusted(key),
            expectedEnv: DomainRegistryClient.expectedEnv, now: .now, highestAcceptedVersion: 0)) {
            XCTAssertEqual($0 as? DomainRegistryVerifier.VerifyError, .badSignature)
        }
    }

    /// End-to-end trust application: a verified registry replaces the bundled
    /// set (and the picker's contents with it), then resets for other tests.
    @MainActor
    func testClientAcceptAppliesVerifiedDomains() throws {
        defer { AuxiliaryDomainRegistry.applyRemote([]) }   // back to bundled
        let key = P256.Signing.PrivateKey()
        let suite = try XCTUnwrap(UserDefaults(suiteName: "domain-registry-tests"))
        suite.removePersistentDomain(forName: "domain-registry-tests")
        let client = DomainRegistryClient(trustedKeys: trusted(key), defaults: suite)
        XCTAssertTrue(client.accept(documentData: try signedDocumentData(key: key)))
        XCTAssertEqual(AuxiliaryDomainRegistry.current.count, 1)
        // Same version again is an idempotent recovery (same canonical transcript),
        // accepted without advancing/lowering the high-water — not a rollback.
        XCTAssertTrue(client.accept(documentData: try signedDocumentData(key: key)))
        XCTAssertEqual(client.highestAcceptedVersion, 5)
    }
}
