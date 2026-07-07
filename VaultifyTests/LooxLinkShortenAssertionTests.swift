import CryptoKit
import XCTest
@testable import Vaultify

/// Shorten-link App Attest binding (`LOOX-APP-ATTEST-SHORTEN-LINK-V1`):
/// byte parity against all 5 frozen vectors (golden + mutation pairs +
/// method normalization) and the token-never-raw property.
final class LooxLinkShortenAssertionTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Binding: Decodable {
            let method: String, path: String
            let challenge_id: String, share_id: String, shorten_token: String
        }
        struct Vector: Decodable {
            let name: String
            let binding: Binding
            let transcript_bytes_hex: String
            let client_data_hash_hex: String
        }
        let vectors: [Vector]
    }

    private func loadVectors() throws -> [Fixture.Vector] {
        let bundle = Bundle(for: LooxLinkShortenAssertionTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "shorten-link-assertion-vectors-v1",
                                           withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).vectors
    }

    func testTranscriptAndHashParityAgainstFrozenVectors() throws {
        let vectors = try loadVectors()
        XCTAssertEqual(vectors.count, 5)
        for vector in vectors {
            let transcript = LooxLinkCanonical.shortenTranscript(
                method: vector.binding.method, path: vector.binding.path,
                challengeId: vector.binding.challenge_id,
                shareId: vector.binding.share_id, shortenToken: vector.binding.shorten_token)
            XCTAssertEqual(transcript.hexString, vector.transcript_bytes_hex,
                           "shorten transcript \(vector.name) drifted")
            XCTAssertEqual(Data(SHA256.hash(data: transcript)).hexString,
                           vector.client_data_hash_hex,
                           "shorten clientDataHash \(vector.name) drifted")
        }
    }

    func testMutationPairsDifferFromGolden() throws {
        let vectors = try loadVectors()
        let golden = try XCTUnwrap(vectors.first { $0.name == "golden" })
        for vector in vectors where vector.name.contains("different") {
            XCTAssertNotEqual(vector.client_data_hash_hex, golden.client_data_hash_hex,
                              "\(vector.name) must not collide with golden")
        }
    }

    func testRawBearerTokenNeverAppearsInTranscript() {
        let token = "stok-AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHH0000"
        let transcript = LooxLinkCanonical.shortenTranscript(
            challengeId: "chal-x", shareId: "share-x", shortenToken: token)
        // Only SHA-256(token) is bound — the bearer itself must not be
        // reconstructable from assertion material.
        XCTAssertNil(transcript.range(of: Data(token.utf8)))
        XCTAssertTrue(transcript.hexString.hasSuffix(
            Data(SHA256.hash(data: Data(token.utf8))).hexString))
    }

    func testDefaultsMatchFrozenEndpoint() {
        // The transcript defaults must always describe the request we send.
        XCTAssertEqual(LooxLinkConfig.shortenPath, "/v1/short-links")
        XCTAssertEqual(LooxLinkCanonical.shortenMethod, "POST")
    }
}
