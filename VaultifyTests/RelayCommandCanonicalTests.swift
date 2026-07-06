import XCTest
@testable import Vaultify

/// P4A signed relay command: byte-parity against the frozen vectors (the
/// worker's contract), plus sign/verify, tamper rejection, and domain
/// separation. The fixed inputs mirror `relay-authz-command-vectors-v1.json`.
final class RelayCommandCanonicalTests: XCTestCase {

    private let pid = Data(repeating: 0x11, count: 32)
    private let nonce = Data(repeating: 0x22, count: 16)
    private let issued: Int64 = 1_760_000_000_000
    private let newPub = Data(repeating: 0x33, count: 65)

    private struct Fixture: Decodable {
        struct Vector: Decodable { let name: String; let canonical_bytes_hex: String }
        let vectors: [Vector]
    }

    private func loadVectors() throws -> [String: String] {
        let bundle = Bundle(for: RelayCommandCanonicalTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "relay-authz-command-vectors-v1", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: fixture.vectors.map { ($0.name, $0.canonical_bytes_hex) })
    }

    private func command(_ kind: RelayCommandKind, epoch: UInt64,
                         aliasID: String? = nil, destination: String? = nil,
                         newPublicKey: Data? = nil) -> RelayCommand {
        RelayCommand(principalID: pid, epoch: epoch, nonce: nonce, issuedAtUnixMs: issued,
                     kind: kind, aliasID: aliasID, destination: destination, newPublicKey: newPublicKey)
    }

    func testByteParityAgainstFrozenVectors() throws {
        let vectors = try loadVectors()
        let cases: [(String, RelayCommand)] = [
            ("createAlias", command(.createAlias, epoch: 1, aliasID: "alias-1")),
            ("disableAlias", command(.disableAlias, epoch: 2, aliasID: "alias-1")),
            ("rotateDestination", command(.rotateDestination, epoch: 3, aliasID: "alias-1", destination: "me@x.com")),
            ("deleteAlias", command(.deleteAlias, epoch: 4, aliasID: "alias-1")),
            ("disableAll", command(.disableAll, epoch: 5)),
            ("rotatePrincipal", command(.rotatePrincipal, epoch: 6, newPublicKey: newPub)),
        ]
        for (name, cmd) in cases {
            XCTAssertEqual(RelayCommandCanonical.transcript(cmd).hexString, vectors[name], "vector \(name) drifted")
        }
    }

    func testSignVerifyRoundTrip() throws {
        let id = RelayPrincipalIdentity.generate()
        let cmd = command(.createAlias, epoch: id.epoch, aliasID: "alias-9")
        let signed = try RelayCommandCanonical.sign(cmd, using: id)
        XCTAssertTrue(RelayCommandCanonical.verify(cmd, signature: signed.signature, x963PublicKey: id.signingPublicKey))
    }

    func testTamperedEpochFailsVerification() throws {
        let id = RelayPrincipalIdentity.generate()
        let cmd = command(.createAlias, epoch: 1, aliasID: "alias-9")
        let signed = try RelayCommandCanonical.sign(cmd, using: id)
        var tampered = cmd; tampered.epoch = 99
        XCTAssertFalse(RelayCommandCanonical.verify(tampered, signature: signed.signature, x963PublicKey: id.signingPublicKey))
    }

    func testDomainSeparationBetweenKinds() {
        // Same scalar fields, different kind → different transcript (type tag).
        let a = command(.createAlias, epoch: 1, aliasID: "x")
        let b = command(.deleteAlias, epoch: 1, aliasID: "x")
        XCTAssertNotEqual(RelayCommandCanonical.transcript(a), RelayCommandCanonical.transcript(b))
    }

    func testEpochDifferenceShowsInBytes() {
        let a = command(.disableAll, epoch: 1)
        let b = command(.disableAll, epoch: 2)
        XCTAssertNotEqual(RelayCommandCanonical.transcript(a), RelayCommandCanonical.transcript(b))
    }
}
