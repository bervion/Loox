import XCTest
@testable import Vaultify

final class RelayDiagnosticsTests: XCTestCase {
    func testSensitiveFieldsAndEmailValuesAreDiscarded() {
        let raw = "stage=api email=fixture@example.test keyId=abc assertion=YWJj http=401 backendCode=key_unknown"
        XCTAssertEqual(RelayDiagnostics.sanitizedMessage(raw), "stage=api http=401 backendCode=key_unknown")
        XCTAssertEqual(RelayDiagnostics.sanitizedMessage("code=fixture@example.test body={\"email\":\"fixture\"}"), "")
    }

    func testOnlyBoundedMetadataIsAccepted() {
        let raw = "stage=attestation host=api-relay.looxpassword.com supported=true code=-34018"
        XCTAssertEqual(RelayDiagnostics.sanitizedMessage(raw), raw)
        XCTAssertEqual(RelayDiagnostics.sanitizedMessage("reason=" + String(repeating: "a", count: 81)), "")
        XCTAssertEqual(RelayDiagnostics.sanitizedMessage("reason=https://example.test code=YWJj=="), "")
    }
}
