import XCTest
@testable import Vaultify

/// P4B relay client: request-body shape (mirrors the signed command) and the
/// genesis public-key rule. Network calls aren't exercised (no live backend in
/// unit tests); the error mapping is covered by the client's typed failures.
final class RelayAPIClientTests: XCTestCase {

    private func command(_ kind: RelayCommandKind, epoch: UInt64 = 1, aliasID: String? = "abc123",
                         destination: String? = nil, newKey: Data? = nil) -> RelayCommand {
        RelayCommand(principalID: Data(repeating: 0x11, count: 32), epoch: epoch,
                     nonce: Data(repeating: 0x22, count: 16), issuedAtUnixMs: 1_760_000_000_000,
                     kind: kind, aliasID: aliasID, destination: destination, newPublicKey: newKey)
    }

    func testBodyMirrorsSignedCommand() {
        let cmd = command(.createAlias)
        let sig = Data(repeating: 0x33, count: 64)
        let body = RelayAPIClient.body(for: cmd, signature: sig, genesisPublicKey: nil)

        XCTAssertEqual(body["kind"] as? Int, 1)
        XCTAssertEqual(body["epoch"] as? UInt64, 1)
        XCTAssertEqual(body["alias_id"] as? String, "abc123")
        XCTAssertEqual(body["principal_id"] as? String, cmd.principalID.base64EncodedString())
        XCTAssertEqual(body["nonce"] as? String, cmd.nonce.base64EncodedString())
        XCTAssertEqual(body["signature"] as? String, sig.base64EncodedString())
        XCTAssertNil(body["public_key"])          // no genesis key when not provided
        XCTAssertNil(body["destination"])         // omitted when nil
        XCTAssertNil(body["new_public_key"])
    }

    func testGenesisPublicKeyIncludedOnlyWhenProvided() {
        let genesisKey = Data(repeating: 0x44, count: 65)
        let body = RelayAPIClient.body(for: command(.createAlias), signature: Data(),
                                       genesisPublicKey: genesisKey)
        XCTAssertEqual(body["public_key"] as? String, genesisKey.base64EncodedString())
    }

    func testKindSpecificFieldsCarried() {
        let rotate = RelayAPIClient.body(
            for: command(.rotateDestination, epoch: 3, destination: "me@x.com"),
            signature: Data(), genesisPublicKey: nil)
        XCTAssertEqual(rotate["kind"] as? Int, 3)
        XCTAssertEqual(rotate["destination"] as? String, "me@x.com")

        let newKey = Data(repeating: 0x55, count: 65)
        let rotatePrincipal = RelayAPIClient.body(
            for: command(.rotatePrincipal, epoch: 6, aliasID: nil, newKey: newKey),
            signature: Data(), genesisPublicKey: nil)
        XCTAssertEqual(rotatePrincipal["kind"] as? Int, 6)
        XCTAssertEqual(rotatePrincipal["new_public_key"] as? String, newKey.base64EncodedString())
        XCTAssertNil(rotatePrincipal["alias_id"])   // disableAll/rotatePrincipal carry no alias
    }

    func testActiveAddressRendersWithLiveDomain() {
        // With the relay live, an active alias renders its full working address.
        let address = AliasAddress.display(localPart: "r7kp2d", status: .active,
                                           relayDomain: RelayConfig.emailDomain,
                                           flag: RelayFeature.activeAliasesEnabled)
        XCTAssertEqual(address, "r7kp2d@relay.looxpassword.com")
    }
}
