import XCTest
@testable import Vaultify

/// v1 share-surface policy: key material (protected multiline — SSH private
/// keys, recovery codes) is absent from Quick Link / Quick View snapshots and
/// is not offerable for per-item Approval sharing. Ordinary login sharing
/// stays intentional. The policy is an explicit allowlist — anything new is
/// excluded until admitted.
final class TransitionalSharePolicyTests: XCTestCase {

    private func field(_ kind: FieldKind, protected: Bool = false,
                       value: String = "x", guard2: Bool? = nil) -> DynamicField {
        DynamicField(label: "F", kind: kind, value: value,
                     protected: protected, guard2: guard2)
    }

    // MARK: Quick Link / Quick View (snapshot shares)

    func testQuickShareDeniesKeyMaterial() {
        XCTAssertFalse(TransitionalSharePolicy.quickShareAllows(field(.multiline, protected: true)),
                       "protected multiline (key material) must never enter a link")
        XCTAssertFalse(TransitionalSharePolicy.quickShareAllows(field(.totp)))
        XCTAssertFalse(TransitionalSharePolicy.quickShareAllows(field(.fileRef)))
        XCTAssertFalse(TransitionalSharePolicy.quickShareAllows(field(.password, guard2: true)))
        XCTAssertFalse(TransitionalSharePolicy.quickShareAllows(field(.password, value: "")))
    }

    func testQuickShareKeepsIntentionalLoginSharing() {
        XCTAssertTrue(TransitionalSharePolicy.quickShareAllows(field(.password, protected: true)))
        XCTAssertTrue(TransitionalSharePolicy.quickShareAllows(field(.username)))
        XCTAssertTrue(TransitionalSharePolicy.quickShareAllows(field(.url)))
        XCTAssertTrue(TransitionalSharePolicy.quickShareAllows(field(.multiline)),
                      "an ordinary note stays shareable")
    }

    func testQuickLinkEnvelopeExcludesSSHPrivateKey() {
        // Exactly as the template creates it: private key protected multiline,
        // public key plain multiline.
        var item = VaultItem(category: .sshKey, title: "Deploy key",
                             fields: ItemCategory.sshKey.fieldTemplate)
        for index in item.fields.indices { item.fields[index].value = "key-material-\(index)" }
        let offered = LooxLinkEnvelope.shareableFields(of: item)
        XCTAssertFalse(offered.contains { $0.protected && $0.kind == .multiline })
        XCTAssertTrue(offered.contains { !$0.protected && $0.kind == .multiline },
                      "the public key remains offerable")
        // Even a hostile selection cannot pull the private key into the built envelope.
        let built = LooxLinkEnvelope.build(item: item, selectedFieldIDs: Set(item.fields.map(\.id)))
        XCTAssertEqual(built.fields.count, 1)
        XCTAssertFalse(built.fields.contains { $0.value.contains("key-material-0") })
    }

    func testQuickLinkEnvelopeExcludesRecoveryCodes() {
        var item = VaultItem(category: .recoveryCodes, title: "Codes",
                             fields: ItemCategory.recoveryCodes.fieldTemplate)
        item.fields[0].value = "111111\n222222"
        XCTAssertTrue(LooxLinkEnvelope.shareableFields(of: item).isEmpty)
    }

    // MARK: Approval sharing (identified recipient)

    func testApprovalDeniesKeyMaterialButKeepsLoginAndTOTPFlows() {
        XCTAssertFalse(TransitionalSharePolicy.approvalShareAllows(field(.multiline, protected: true)))
        XCTAssertFalse(TransitionalSharePolicy.approvalShareAllows(field(.fileRef)))
        XCTAssertFalse(TransitionalSharePolicy.approvalShareAllows(field(.password, guard2: true)))
        XCTAssertTrue(TransitionalSharePolicy.approvalShareAllows(field(.password, protected: true)))
        XCTAssertTrue(TransitionalSharePolicy.approvalShareAllows(field(.totp)),
                      "TOTP keeps its own tri-state capability flow")
        XCTAssertTrue(TransitionalSharePolicy.approvalShareAllows(field(.multiline)))
    }
}
