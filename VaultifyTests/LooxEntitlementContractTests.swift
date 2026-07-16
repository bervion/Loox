import XCTest
@testable import Vaultify

/// Pins the app side of the Loox Entitlement contract (v1, BE handoff 260716):
/// the binding-hash parity vectors frozen by the backend, and the attach
/// response wire shape. A failure here means the CONTRACT drifted — resolve
/// with the backend team, never by editing the expectation.
final class LooxEntitlementContractTests: XCTestCase {

    // MARK: Binding-hash byte parity (frozen backend vectors)

    func testRelayPrincipalBindingHashMatchesTheFrozenVector() {
        // Standard base64 WITH padding — exactly the `principal_id` string
        // RelayAPIClient sends (the server normalizes url-safe to this form
        // before hashing; the app must hash the same canonical).
        XCTAssertEqual(
            LooxBindingHash.hex("AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="),
            "905f28def18eaac05ae6f12b2c3452744afaf626da1343d57b395b544e0519b6")
    }

    func testLinkAttestKeyBindingHashMatchesTheFrozenVector() {
        XCTAssertEqual(
            LooxBindingHash.hex("ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8="),
            "b919fd68efaadd92c9f96482c1477a28083e94a93fa7e10be6237ca824c22a06")
    }

    func testQuickViewAttestKeyBindingHashMatchesTheFrozenVector() {
        XCTAssertEqual(
            LooxBindingHash.hex("QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8="),
            "d97d14cfb5bf28ccbb6e8d5651376b753376242452d744938635699be672050a")
    }

    func testBindingHashNeverNormalizes() {
        // No trim, no case folding, no decode-then-hash: byte-different
        // inputs must hash differently even when they decode identically.
        let padded = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
        XCTAssertNotEqual(LooxBindingHash.hex(padded), LooxBindingHash.hex(" " + padded))
        XCTAssertNotEqual(LooxBindingHash.hex(padded), LooxBindingHash.hex(padded.lowercased()))
    }

    // MARK: Attach wire shapes

    func testAttachResponseDecodesTheContractShape() throws {
        let json = """
        {"tier":"max","status":"active","expires_at_ms":1234,"environment":"Sandbox",
         "authorizations":[
           {"service":"relay","binding_type":"relay_principal","binding_required":true,
            "grant":"g1","lease":"l1","lease_expires_at_ms":99},
           {"service":"link","binding_type":"attest_key_link","binding_required":false,
            "lease":"l2","lease_expires_at_ms":88},
           {"service":"quickview","binding_type":"attest_key_qv","error":"binding_conflict"}
         ]}
        """
        let response = try JSONDecoder().decode(LooxAttachResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.tier, "max")
        XCTAssertEqual(response.environment, "Sandbox")
        XCTAssertEqual(response.authorizations.count, 3)
        XCTAssertEqual(response.authorizations[0].grant, "g1")
        XCTAssertEqual(response.authorizations[1].bindingRequired, false)
        XCTAssertNil(response.authorizations[1].grant)
        XCTAssertEqual(response.authorizations[2].error, "binding_conflict")
    }

    func testAttachRequestEncodesSnakeCaseKeys() throws {
        let binding = LooxAttachBindingRequest(
            service: "link", bindingType: "attest_key_link",
            bindingValueHash: "ab12", replaceBindingId: 7)
        let data = try JSONEncoder().encode(binding)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["binding_type"] as? String, "attest_key_link")
        XCTAssertEqual(object["binding_value_hash"] as? String, "ab12")
        XCTAssertEqual(object["replace_binding_id"] as? Int, 7)
        XCTAssertEqual(object["service"] as? String, "link")
    }
}
