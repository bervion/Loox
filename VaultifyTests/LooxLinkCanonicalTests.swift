import XCTest
@testable import Vaultify

/// M0 hard gate: Swift's canonical create-share transcript must be
/// byte-identical to the Worker's. Vectors are loaded from the frozen fixture
/// (`app-attest-create-share-vectors-v1.json`) — never retyped, so a shared
/// bug can't hide in duplicated constants.
final class LooxLinkCanonicalTests: XCTestCase {

    private struct VectorFile: Decodable {
        let vectors: [Vector]
    }

    private struct Vector: Decodable {
        let name: String
        let method: String
        let path: String
        let challenge_id: String
        let ciphertext_b64: String
        let ciphertext_sha256_hex: String
        let iv_b64: String
        let crypto_version: UInt32
        let expires_in_seconds: UInt64
        let envelope_b64: String?
        let canonical_bytes_hex: String
        let request_hash_hex: String
    }

    private func loadVectors() throws -> [Vector] {
        let bundle = Bundle(for: LooxLinkCanonicalTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "app-attest-create-share-vectors-v1", withExtension: "json"),
            "fixture missing from test bundle — check Project.swift test resources")
        return try JSONDecoder().decode(VectorFile.self, from: Data(contentsOf: url)).vectors
    }

    func testTranscriptAndHashParityAgainstFrozenVectors() throws {
        let vectors = try loadVectors()
        XCTAssertEqual(vectors.count, 5, "vector file should carry 5 frozen vectors")

        for vector in vectors {
            let ciphertext = try XCTUnwrap(Data(base64Encoded: vector.ciphertext_b64), vector.name)
            let iv = try XCTUnwrap(Data(base64Encoded: vector.iv_b64), vector.name)
            // null → absent; "" → present with zero bytes. Both encode as u32(0).
            let envelope = vector.envelope_b64.flatMap { Data(base64Encoded: $0) }

            let transcript = LooxLinkCanonical.transcript(
                method: vector.method, path: vector.path,
                challengeId: vector.challenge_id,
                ciphertext: ciphertext, iv: iv,
                cryptoVersion: vector.crypto_version,
                expiresInSeconds: vector.expires_in_seconds,
                envelope: envelope)
            XCTAssertEqual(hex(transcript), vector.canonical_bytes_hex,
                           "transcript bytes diverge for vector: \(vector.name)")

            let hash = LooxLinkCanonical.requestHash(
                method: vector.method, path: vector.path,
                challengeId: vector.challenge_id,
                ciphertext: ciphertext, iv: iv,
                cryptoVersion: vector.crypto_version,
                expiresInSeconds: vector.expires_in_seconds,
                envelope: envelope)
            XCTAssertEqual(hex(hash), vector.request_hash_hex,
                           "request hash diverges for vector: \(vector.name)")
        }
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
