#if compiler(>=6.2)
import CryptoKit
import XCTest
@testable import Vaultify

/// Credential Exchange mapper tests.
///
/// NOTE: constructing the `ASImportable*` / `ASExportedCredentialData` value
/// types HARD-CRASHES at runtime on the iOS 27.0 beta simulator (a trap inside
/// the SDK types, not our logic — the pure key-encoding test below, which
/// touches none of them, passes). So the export→import round-trip tests cannot
/// run on current tooling and are deferred to a stable iOS 26.1+ runtime / device
/// (see the phase-07 discovery report). Only the SDK-free key encoding is
/// verifiable here.
@available(iOS 26.1, *)
final class CredentialExchangeMappingTests: XCTestCase {

    func testPasskeyKeyEncodingRoundTripsLosslessly() throws {
        let raw = P256.Signing.PrivateKey().rawRepresentation
        let encoded = try XCTUnwrap(CredentialExchangeMapping.encodePasskeyKey(raw))
        XCTAssertEqual(CredentialExchangeMapping.decodePasskeyKey(encoded), raw)
    }

    func testPasskeyKeyDecodeRejectsGarbage() {
        XCTAssertNil(CredentialExchangeMapping.decodePasskeyKey(Data([0x00, 0x01, 0x02])))
    }
}
#endif
