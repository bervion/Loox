import XCTest
@testable import Vaultify

/// The exhaustive capability contract: every registered template has an
/// explicit, intentional matrix; unknown identity means ZERO external
/// capability; field policy fails closed on key material and unknown roles;
/// and no capability ever depends on an editable label.
final class ItemCapabilityResolverTests: XCTestCase {

    private func item(kind: ItemKindID, category: ItemCategory = .custom,
                      fields: [DynamicField] = []) -> VaultItem {
        var item = VaultItem(category: category, title: "T", fields: fields)
        item.semantics = ItemSemantics(kindID: kind)
        return item
    }

    // MARK: Registry completeness

    func testEveryTemplateHasAnExplicitCapabilityMatrix() {
        // Compiler-visible completeness: every registered kind resolves; the
        // expected matrix below must be extended when a template is added —
        // a new type CANNOT ship with an accidental policy.
        let expectations: [ItemKindID: (autofill: Bool, audit: Bool, space: Bool, quick: Bool)] = [
            .login: (true, true, true, true),
            .secureNote: (false, false, false, true),
            .paymentCard: (false, false, false, true),
            .personalIdentity: (false, false, false, true),
            .sshKey: (false, false, false, true),
            .recoveryCodes: (false, false, false, false),
            .securityQuestions: (false, false, false, true),
            .custom: (true, true, false, true),
            .apiSecret: (false, false, false, false),
            .gitAccount: (false, false, false, true),
            .ascAPIKey: (false, false, false, false),
            .apnsKey: (false, false, false, false),
            .signingIdentity: (false, false, false, false),
            .provisioningProfile: (false, false, false, false),
            .tlsCertificate: (false, false, false, false),
        ]
        XCTAssertEqual(Set(ItemTemplateRegistry.all.map(\.kindID)), Set(expectations.keys),
                       "registry and expectation table must cover the same kinds")
        for (kind, expected) in expectations {
            let caps = ItemCapabilityResolver.capabilities(for: item(kind: kind))
            XCTAssertEqual(caps.loginAutoFill, expected.autofill, "\(kind.rawValue) autofill")
            XCTAssertEqual(caps.passwordAudit, expected.audit, "\(kind.rawValue) audit")
            XCTAssertEqual(caps.spaceShareEligible, expected.space, "\(kind.rawValue) space")
            XCTAssertEqual(caps.quickShareEligible, expected.quick, "\(kind.rawValue) quick")
        }
    }

    func testDeveloperSecretsAreAbsentFromEveryLoginSurface() {
        for kind in [ItemKindID.apiSecret, .sshKey, .ascAPIKey, .apnsKey,
                     .signingIdentity, .provisioningProfile, .tlsCertificate] {
            let caps = ItemCapabilityResolver.capabilities(for: item(kind: kind))
            XCTAssertFalse(caps.loginAutoFill, kind.rawValue)
            XCTAssertFalse(caps.totpSource, kind.rawValue)
            XCTAssertFalse(caps.safariLoginListing, kind.rawValue)
            XCTAssertFalse(caps.passwordAudit, kind.rawValue)
            XCTAssertFalse(caps.identityFill, kind.rawValue)
            XCTAssertFalse(caps.cardFill, kind.rawValue)
            XCTAssertFalse(caps.spaceShareEligible, kind.rawValue)
            XCTAssertFalse(caps.csvCredentialExport, kind.rawValue)
        }
    }

    /// A token typed as `.password` on a developer item must not become a
    /// fillable login or an audit candidate.
    func testAPITokenAsPasswordKindGainsNothing() {
        let token = DynamicField(label: "Token", kind: .password, value: "ghp_secret",
                                 semantics: FieldSemantics(roleID: .apiToken))
        let api = item(kind: .apiSecret, fields: [token])
        XCTAssertFalse(ItemCapabilityResolver.isFillableLogin(api))
        XCTAssertFalse(ItemCapabilityResolver.capabilities(for: api).passwordAudit)
        let fieldCaps = ItemCapabilityResolver.capabilities(for: token, in: api)
        XCTAssertFalse(fieldCaps.quickShare)
        XCTAssertFalse(fieldCaps.approvalShare)
        XCTAssertFalse(fieldCaps.plaintextExport)
    }

    // MARK: Fail closed

    func testUnknownKindHasZeroCapability() {
        let mystery = item(kind: ItemKindID("future.wormhole-credential"),
                           fields: [DynamicField(label: "Password", kind: .password, value: "x")])
        XCTAssertEqual(ItemCapabilityResolver.capabilities(for: mystery), .none)
        XCTAssertFalse(ItemCapabilityResolver.isFillableLogin(mystery))
    }

    func testUnknownCategoryRawHasZeroCapability() {
        var mystery = VaultItem(category: .custom, title: "T",
                                fields: [DynamicField(label: "Password", kind: .password, value: "x")])
        mystery.unknownCategoryRaw = "quantumPass"
        XCTAssertEqual(ItemCapabilityResolver.capabilities(for: mystery), .none)
    }

    func testUnknownRoleFieldNeverLeaves() {
        let login = ItemTemplateRegistry.definition(for: .login)!
        var vaultItem = VaultItem(category: .login, title: "L", fields: login.defaultFields)
        vaultItem.semantics = login.newItemSemantics
        let alien = DynamicField(label: "Alien", kind: .text, value: "v",
                                 semantics: FieldSemantics(roleID: FieldRoleID("alien.role")))
        vaultItem.fields.append(alien)
        let caps = ItemCapabilityResolver.capabilities(for: alien, in: vaultItem)
        XCTAssertFalse(caps.quickShare)
        XCTAssertFalse(caps.approvalShare)
        XCTAssertFalse(caps.plaintextExport)
        XCTAssertFalse(caps.searchIndex)
        XCTAssertEqual(caps.revealAuthorization, .reauthenticate)
    }

    /// A known role carried on the WRONG template transfers no policy.
    func testRoleOnWrongTemplateIsTreatedAsUnknown() {
        let sshRoleOnNote = DynamicField(label: "Key", kind: .multiline, value: "x",
                                         semantics: FieldSemantics(roleID: .sshPrivateKey))
        let note = item(kind: .secureNote, category: .note, fields: [sshRoleOnNote])
        let caps = ItemCapabilityResolver.capabilities(for: sshRoleOnNote, in: note)
        XCTAssertFalse(caps.quickShare)
        XCTAssertFalse(caps.approvalShare)
        XCTAssertEqual(caps.revealAuthorization, .reauthenticate)
    }

    // MARK: Key material

    func testSSHPrivateKeyFieldNeverLeavesButPublicKeyMay() {
        let ssh = ItemTemplateRegistry.definition(for: .sshKey)!
        var vaultItem = VaultItem(category: .sshKey, title: "Key", fields: ssh.defaultFields)
        vaultItem.semantics = ssh.newItemSemantics
        for index in vaultItem.fields.indices { vaultItem.fields[index].value = "value-\(index)" }

        let priv = vaultItem.fields.first { $0.roleID == .sshPrivateKey }!
        let pub = vaultItem.fields.first { $0.roleID == .sshPublicKey }!

        let privCaps = ItemCapabilityResolver.capabilities(for: priv, in: vaultItem)
        XCTAssertEqual(privCaps.sensitivity, .keyMaterial)
        XCTAssertFalse(privCaps.quickShare)
        XCTAssertFalse(privCaps.approvalShare)
        XCTAssertFalse(privCaps.plaintextExport)
        XCTAssertFalse(privCaps.searchIndex)
        XCTAssertEqual(privCaps.revealAuthorization, .reauthenticate)

        let pubCaps = ItemCapabilityResolver.capabilities(for: pub, in: vaultItem)
        XCTAssertTrue(pubCaps.quickShare, "a public key is public material")
        XCTAssertEqual(pubCaps.sensitivity, .public)
    }

    /// Stored policy can TIGHTEN the registry minimum but never relax it.
    func testStoredPolicyOnlyTightens() {
        let ssh = ItemTemplateRegistry.definition(for: .sshKey)!
        var vaultItem = VaultItem(category: .sshKey, title: "Key", fields: ssh.defaultFields)
        vaultItem.semantics = ssh.newItemSemantics
        // Hostile/imported payload claims the private key is public and free.
        if let index = vaultItem.fields.firstIndex(where: { $0.roleID == .sshPrivateKey }) {
            vaultItem.fields[index].value = "SECRET"
            vaultItem.fields[index].semantics?.sensitivity = .public
            vaultItem.fields[index].semantics?.actionAuthorization = ActionAuthorization.none
        }
        let priv = vaultItem.fields.first { $0.roleID == .sshPrivateKey }!
        let caps = ItemCapabilityResolver.capabilities(for: priv, in: vaultItem)
        XCTAssertEqual(caps.sensitivity, .keyMaterial, "registry minimum wins")
        XCTAssertEqual(caps.revealAuthorization, .reauthenticate)
        XCTAssertFalse(caps.quickShare)
    }

    // MARK: Labels are never authority

    func testRelabelingChangesNoCapability() {
        let login = ItemTemplateRegistry.definition(for: .login)!
        var vaultItem = VaultItem(category: .login, title: "L", fields: login.defaultFields)
        vaultItem.semantics = login.newItemSemantics
        for index in vaultItem.fields.indices { vaultItem.fields[index].value = "v" }
        let before = vaultItem.fields.map {
            ItemCapabilityResolver.capabilities(for: $0, in: vaultItem)
        }
        for index in vaultItem.fields.indices {
            vaultItem.fields[index].label = "Nhãn tùy chỉnh \(index)"
        }
        let after = vaultItem.fields.map {
            ItemCapabilityResolver.capabilities(for: $0, in: vaultItem)
        }
        XCTAssertEqual(before, after)
        XCTAssertEqual(ItemCapabilityResolver.capabilities(for: vaultItem),
                       ItemTemplateRegistry.definition(for: .login)!.capabilities)
    }

    // MARK: Legacy parity

    func testLegacyCategoryParityMatrix() {
        // Pre-semantic items (no kindID) resolve through their category to the
        // SAME registry definition — the eight shipped categories keep their
        // intentional behavior.
        for category in ItemCategory.allCases {
            let legacy = VaultItem(category: category, title: "T",
                                   fields: category.fieldTemplate)
            let viaCategory = ItemCapabilityResolver.capabilities(for: legacy)
            let viaKind = ItemTemplateRegistry.definition(forLegacy: category)!.capabilities
            XCTAssertEqual(viaCategory, viaKind, "\(category)")
        }
    }

    func testLegacyCustomWithPasswordStillFills() {
        let custom = VaultItem(category: .custom, title: "My router",
                               fields: [DynamicField(label: "Password", kind: .password, value: "x")])
        XCTAssertTrue(ItemCapabilityResolver.isFillableLogin(custom),
                      "shipped duck-typing parity: custom items with passwords fill")
    }

    func testLegacySSHKeyNeverFills() {
        var fields = ItemCategory.sshKey.fieldTemplate
        fields.append(DynamicField(label: "Passphrase", kind: .password, value: "pw"))
        let ssh = VaultItem(category: .sshKey, title: "Key", fields: fields)
        XCTAssertFalse(ItemCapabilityResolver.isFillableLogin(ssh),
                       "an SSH passphrase typed as .password must not become a login")
    }
}
