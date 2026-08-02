import XCTest
@testable import Vaultify

/// Wire contract of the additive semantic layer: legacy payloads decode
/// unchanged, semantic payloads round-trip losslessly, unknown identifiers
/// survive, and a NEWER incompatible schema marks the item read-only instead
/// of destroying or rewriting it.
final class SemanticsWireTests: XCTestCase {

    // MARK: DynamicField

    func testLegacyFieldJSONDecodesWithoutSemantics() throws {
        let legacy = Data("""
        {"id":"f1","label":"Password","kind":"password","value":"hunter2","protected":true}
        """.utf8)
        let field = try JSONDecoder().decode(DynamicField.self, from: legacy)
        XCTAssertNil(field.semantics)
        XCTAssertNil(field.unknownKindRaw)
        XCTAssertEqual(field.kind, .password)
        // Re-encode omits the semantics key entirely (no wire noise for
        // pre-semantic readers).
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(field), encoding: .utf8))
        XCTAssertFalse(json.contains("semantics"))
    }

    func testFieldSemanticsRoundTrip() throws {
        var field = DynamicField(label: "Token", kind: .password, value: "tok",
                                 semantics: FieldSemantics(
                                     roleID: .apiToken, sectionID: "core",
                                     sensitivity: .secret,
                                     actionAuthorization: .reauthenticate))
        field.semantics?.lifecycle = FieldLifecycle(rotateDays: 90)
        let round = try JSONDecoder().decode(DynamicField.self,
                                             from: JSONEncoder().encode(field))
        XCTAssertEqual(round.semantics?.roleID, .apiToken)
        XCTAssertEqual(round.semantics?.sensitivity, .secret)
        XCTAssertEqual(round.semantics?.actionAuthorization, .reauthenticate)
        XCTAssertEqual(round.semantics?.lifecycle?.rotateDays, 90)
    }

    func testUnknownFieldKindRoundTripsLosslessly() throws {
        let futuristic = Data("""
        {"id":"f1","label":"Hologram","kind":"hologram","value":"x","protected":false}
        """.utf8)
        let field = try JSONDecoder().decode(DynamicField.self, from: futuristic)
        XCTAssertEqual(field.kind, .text, "presentation degrades to plain text")
        XCTAssertEqual(field.unknownKindRaw, "hologram")
        let reEncoded = try JSONEncoder().encode(field)
        let raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: reEncoded) as? [String: Any])
        XCTAssertEqual(raw["kind"] as? String, "hologram",
                       "an edit-save cycle must never rewrite an unknown kind")
    }

    func testUnknownRoleIDIsPreservedVerbatim() throws {
        let json = Data("""
        {"id":"f1","label":"X","kind":"text","value":"v","protected":false,
         "semantics":{"roleID":"quantum.entangled-key","sectionID":"future"}}
        """.utf8)
        let field = try JSONDecoder().decode(DynamicField.self, from: json)
        XCTAssertEqual(field.roleID?.rawValue, "quantum.entangled-key")
        let round = try JSONDecoder().decode(DynamicField.self,
                                             from: JSONEncoder().encode(field))
        XCTAssertEqual(round.roleID?.rawValue, "quantum.entangled-key")
    }

    func testUnknownPolicyEnumValueDecodesLenientlyWithoutFailingTheField() throws {
        let json = Data("""
        {"id":"f1","label":"X","kind":"text","value":"v","protected":false,
         "semantics":{"roleID":"api.token","sensitivity":"radioactive"}}
        """.utf8)
        let field = try JSONDecoder().decode(DynamicField.self, from: json)
        XCTAssertEqual(field.roleID, .apiToken)
        XCTAssertNil(field.semantics?.sensitivity,
                     "unknown policy value degrades to nil; registry minimum governs")
    }

    // MARK: ItemSecret + schema versions

    func testItemSemanticsRoundTripThroughSecret() throws {
        var item = VaultItem(category: .custom, title: "API",
                             fields: [DynamicField(label: "Token", kind: .password, value: "t")])
        item.semantics = ItemSemantics(kindID: .apiSecret, templateVersion: 1,
                                       links: [ItemLink(roleID: LinkRole.recovery,
                                                        targetItemId: "target-1")])
        let secret = try JSONDecoder().decode(ItemSecret.self,
                                              from: JSONEncoder().encode(item.secret))
        XCTAssertEqual(secret.semantics?.kindID, .apiSecret)
        XCTAssertEqual(secret.semantics?.schemaVersion, ItemSemantics.supported)
        XCTAssertEqual(secret.semantics?.links?.first?.targetItemId, "target-1")
    }

    func testLegacySecretWithoutSemanticsDecodes() throws {
        let legacy = Data("""
        {"title":"Login","category":"login",
         "fields":[{"id":"f","label":"Password","kind":"password","value":"x","protected":true}],
         "tags":[]}
        """.utf8)
        let secret = try JSONDecoder().decode(ItemSecret.self, from: legacy)
        XCTAssertNil(secret.semantics)
    }

    func testUnsupportedFutureSchemaMarksItemReadOnly() throws {
        let future = Data("""
        {"title":"Future","category":"login","fields":[],"tags":[],
         "semantics":{"schemaVersion":\(ItemSemantics.supported + 1),"kindID":"future.kind"}}
        """.utf8)
        let secret = try JSONDecoder().decode(ItemSecret.self, from: future)
        var item = VaultItem(category: secret.category, title: secret.title, fields: secret.fields)
        item.semantics = secret.semantics
        XCTAssertTrue(item.isUnsupportedSchema)
        XCTAssertEqual(ItemCapabilityResolver.capabilities(for: item), .none)
    }

    @MainActor
    func testRepositoryRefusesToResealUnsupportedSchema() throws {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session,
                                   externalSideEffectsEnabled: false)
        repo.reload()
        TestLifetimeRetainer.retain(repo)

        var item = VaultItem(category: .login, title: "Future item", fields: [])
        item.semantics = ItemSemantics(schemaVersion: ItemSemantics.supported + 1)
        // update() on an unsupported item is a no-op — never a typed re-encode.
        try repo.update(item)
        XCTAssertTrue(repo.items.isEmpty)
    }
}
