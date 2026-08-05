import XCTest
@testable import Vaultify

/// The invariant binding the two tables that must agree: every role
/// `LegacySemanticsInference` can stamp on a field MUST resolve to a descriptor
/// in the template its category maps to.
///
/// When they disagree the resolver sees a role it cannot find and fails closed
/// to `.reauthenticate` + `.secret` — which shipped as Face ID on every 2FA and
/// Website copy, and silently dropped both fields from Quick Share, because the
/// login template declared policy for only username and password. A registry
/// list that doubles as a policy table cannot be allowed to drift from the
/// inference that feeds it.
final class InferredRolePolicyTests: XCTestCase {

    /// A login carrying the two optional fields real logins pick up: an
    /// imported one-time code and a website.
    private func loginWithWebsiteAndTOTP() -> VaultItem {
        var login = VaultItem(category: .login, title: "GitHub",
                              fields: ItemCategory.login.fieldTemplate)
        login.fields.append(DynamicField(label: "2FA", kind: .totp, value: "SEED"))
        login.fields.append(DynamicField(label: "Site", kind: .url, value: "github.com"))
        return login
    }

    /// Every category inference understands, populated with the field shapes it
    /// can prove a role for.
    private func inferredItems() -> [VaultItem] {
        [loginWithWebsiteAndTOTP()]
            + [ItemCategory.note, .sshKey, .recoveryCodes, .card, .identity,
               .securityQuestions, .custom].map {
                VaultItem(category: $0, title: "T", fields: $0.fieldTemplate)
            }
    }

    func testEveryInferredRoleHasATemplateDescriptor() {
        for item in inferredItems() {
            let inferred = LegacySemanticsInference.applied(to: item)
            guard let kindID = inferred.semantics?.kindID,
                  let template = ItemTemplateRegistry.definition(for: kindID) else { continue }
            for field in inferred.fields {
                guard let roleID = field.roleID else { continue }
                XCTAssertNotNil(
                    template.descriptor(for: roleID),
                    """
                    \(kindID.rawValue) template declares no descriptor for the \
                    inferred role \(roleID.rawValue) — the resolver will treat \
                    it as an unknown role and force device-owner re-auth.
                    """)
            }
        }
    }

    /// The user-visible half of the same invariant: copying a 2FA code or a
    /// website must never raise a biometric prompt.
    func testLoginWebsiteAndTOTPCopyWithoutReauth() {
        let inferred = LegacySemanticsInference.applied(to: loginWithWebsiteAndTOTP())
        for kind in [FieldKind.totp, .url] {
            guard let field = inferred.fields.first(where: { $0.kind == kind }) else {
                return XCTFail("missing \(kind.rawValue) field")
            }
            XCTAssertEqual(ItemCapabilityResolver.capabilities(for: field, in: inferred)
                            .revealAuthorization, .none,
                           "\(kind.rawValue) must copy without a biometric prompt")
        }
    }

    /// The website field is snapshot-shareable; the 2FA field is not, but for a
    /// reason that has nothing to do with roles — `quickShareKindAllows` excludes
    /// the `.totp` KIND outright, so a passing role policy must not be read as
    /// permission to share a seed.
    func testWebsiteStaysQuickShareableAndTOTPNeverIs() {
        let inferred = LegacySemanticsInference.applied(to: loginWithWebsiteAndTOTP())
        let website = inferred.fields.first { $0.kind == .url }
        let totp = inferred.fields.first { $0.kind == .totp }
        XCTAssertEqual(website.map {
            ItemCapabilityResolver.capabilities(for: $0, in: inferred).quickShare
        }, true)
        XCTAssertEqual(totp.map {
            ItemCapabilityResolver.capabilities(for: $0, in: inferred).quickShare
        }, false)
    }

    /// Policy parity with what the app itself creates: the website field is
    /// plain, the one-time code carries a seed.
    func testLoginOptionalDescriptorsCarryParitySensitivity() {
        guard let template = ItemTemplateRegistry.definition(for: .login) else {
            return XCTFail("login template missing")
        }
        XCTAssertEqual(template.descriptor(for: .website)?.sensitivity, .private)
        XCTAssertEqual(template.descriptor(for: .totp)?.sensitivity, .secret)
        // Neither may join the default field set: a new login opens with
        // username and password only.
        XCTAssertEqual(template.descriptor(for: .website)?.isDefault, false)
        XCTAssertEqual(template.descriptor(for: .totp)?.isDefault, false)
        XCTAssertEqual(ItemCategory.login.fieldTemplate.count, 2)
    }
}
