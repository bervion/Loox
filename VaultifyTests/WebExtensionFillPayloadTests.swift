import XCTest
@testable import Vaultify

/// Tests for the web extension's fill-payload path: the ONLY native command
/// that releases field values for page injection. Covers single-item scope,
/// category gating, secret-kind exclusion, canonical key mapping, expiry
/// normalization, and the router-level authorization rejections.
@MainActor
final class WebExtensionFillPayloadTests: XCTestCase {

    private var store: VaultStore!
    private let keyBytes = [UInt8](repeating: 7, count: 32)
    private var key: SecureBytes { SecureBytes(keyBytes) }

    override func setUp() {
        super.setUp()
        store = VaultStore(inMemory: true)
    }

    // MARK: - Fixtures

    private func fullIdentity(id: String = UUID().uuidString) -> VaultItem {
        VaultItem(id: id, category: .identity, title: "Me", fields: [
            DynamicField(label: "Full Name", kind: .text, value: "Mary Jane Smith"),
            DynamicField(label: "Email", kind: .email, value: "me@example.com"),
            DynamicField(label: "Phone", kind: .phone, value: "+84 90 123 4567"),
            DynamicField(label: "Address", kind: .multiline, value: "1 Main St\nHanoi"),
            DynamicField(label: "ID Number", kind: .monospace, value: "ID-9999", protected: true),
        ])
    }

    private func fullCard(id: String = UUID().uuidString,
                          expiry: String = "09/27") -> VaultItem {
        VaultItem(id: id, category: .card, title: "Main Card", fields: [
            DynamicField(label: "Cardholder", kind: .text, value: "MARY SMITH"),
            DynamicField(label: "Card Number", kind: .monospace,
                         value: "4111 1111 1111 1111", protected: true),
            DynamicField(label: "Expiry", kind: .text, value: expiry),
            DynamicField(label: "Security Code", kind: .monospace,
                         value: "123", protected: true),
            DynamicField(label: "PIN", kind: .number, value: "0000", protected: true),
        ])
    }

    // MARK: - Identity payload

    func testIdentityPayloadCanonicalKeys() throws {
        let item = fullIdentity()
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let values = try WebExtensionReader.fillPayload(itemId: item.id, category: .identity,
                                                        store: store, key: key)
        XCTAssertEqual(values["fullName"], "Mary Jane Smith")
        XCTAssertEqual(values["givenName"], "Mary Jane")
        XCTAssertEqual(values["familyName"], "Smith")
        XCTAssertEqual(values["email"], "me@example.com")
        XCTAssertEqual(values["phone"], "+84 90 123 4567")
        XCTAssertEqual(values["address"], "1 Main St\nHanoi")
        XCTAssertNil(values.values.first(where: { $0.contains("ID-9999") }),
                     "a protected identity field must never be released for fill")
    }

    func testIdentityPayloadRespectsProtectedFlag() throws {
        let item = VaultItem(category: .identity, title: "Guarded", fields: [
            DynamicField(label: "Email", kind: .email,
                         value: "secret@example.com", protected: true),
        ])
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let values = try WebExtensionReader.fillPayload(itemId: item.id, category: .identity,
                                                        store: store, key: key)
        XCTAssertNil(values["email"])
    }

    func testIdentityPayloadNeverContainsPasswordKindValue() throws {
        // A malformed/imported identity carrying a password field must not
        // leak it through the fill channel.
        let item = VaultItem(category: .identity, title: "Odd", fields: [
            DynamicField(label: "Full Name", kind: .text, value: "A B"),
            DynamicField(label: "Password", kind: .password, value: "sup3r-secret"),
        ])
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let values = try WebExtensionReader.fillPayload(itemId: item.id, category: .identity,
                                                        store: store, key: key)
        XCTAssertFalse(values.values.contains("sup3r-secret"))
    }

    func testAddressIsLabelStrict() throws {
        let item = VaultItem(category: .identity, title: "NoteOnly", fields: [
            DynamicField(label: "Notes", kind: .multiline, value: "private ramblings"),
        ])
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let values = try WebExtensionReader.fillPayload(itemId: item.id, category: .identity,
                                                        store: store, key: key)
        XCTAssertNil(values["address"], "an unlabeled multiline must not become an address")
    }

    // MARK: - Card payload

    func testCardPayloadCanonicalKeysAndDigitStripping() throws {
        let item = fullCard()
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let values = try WebExtensionReader.fillPayload(itemId: item.id, category: .card,
                                                        store: store, key: key)
        XCTAssertEqual(values["ccName"], "MARY SMITH")
        XCTAssertEqual(values["ccNumber"], "4111111111111111", "PAN released digits-only")
        XCTAssertEqual(values["ccExpMonth"], "09")
        XCTAssertEqual(values["ccExpYear"], "2027")
        XCTAssertEqual(values["ccExp"], "09/27")
        XCTAssertEqual(values["ccCsc"], "123")
        XCTAssertFalse(values.values.contains("0000"), "PIN must never be released")
    }

    func testCardExpiryFourDigitYearNormalized() throws {
        let item = fullCard(expiry: "9/2027")
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let values = try WebExtensionReader.fillPayload(itemId: item.id, category: .card,
                                                        store: store, key: key)
        XCTAssertEqual(values["ccExpMonth"], "09")
        XCTAssertEqual(values["ccExpYear"], "2027")
        XCTAssertEqual(values["ccExp"], "09/27")
    }

    func testCardLevel2SealedNumberNotReleased() throws {
        let item = VaultItem(category: .card, title: "Sealed", fields: [
            DynamicField(label: "Card Number", kind: .monospace,
                         value: "4111111111111111", protected: true, guard2: true),
        ])
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let values = try WebExtensionReader.fillPayload(itemId: item.id, category: .card,
                                                        store: store, key: key)
        XCTAssertNil(values["ccNumber"], "Level-2 sealed values never leave the vault")
    }

    func testCardSecretGuardSealedNumberNotReleasedEvenWithoutGuard2() throws {
        // A SecretGuard payload is a tagged base64 blob; its stray digits must
        // never be released as a card number. The check must run on the RAW
        // stored value: after digit-stripping the tag is gone by construction,
        // so a digits-only check can never fire. guard2 deliberately unset to
        // exercise the SecretGuard layer alone (e.g. a migrated/synced record).
        let item = VaultItem(category: .card, title: "Sealed", fields: [
            DynamicField(label: "Card Number", kind: .monospace,
                         value: "v2g:99887766554433221100AAAA", protected: true),
        ])
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let values = try WebExtensionReader.fillPayload(itemId: item.id, category: .card,
                                                        store: store, key: key)
        XCTAssertNil(values["ccNumber"],
                     "SecretGuard-sealed values never leave the vault, guard2 or not")
    }

    // MARK: - Scope + category gating

    func testPayloadContainsOnlyRequestedItem() throws {
        let wanted = fullIdentity()
        let other = VaultItem(category: .identity, title: "Other", fields: [
            DynamicField(label: "Email", kind: .email, value: "other@example.com"),
        ])
        try WebExtensionTestSeed.insert(wanted, into: store, key: key)
        try WebExtensionTestSeed.insert(other, into: store, key: key)
        let values = try WebExtensionReader.fillPayload(itemId: wanted.id, category: .identity,
                                                        store: store, key: key)
        XCTAssertFalse(values.values.contains("other@example.com"),
                       "payload must be scoped to the single requested item")
    }

    func testCategoryMismatchForbidden() throws {
        let identity = fullIdentity()
        try WebExtensionTestSeed.insert(identity, into: store, key: key)
        XCTAssertThrowsError(try WebExtensionReader.fillPayload(
            itemId: identity.id, category: .card, store: store, key: key)) { error in
            XCTAssertEqual(error as? WebExtensionReader.ReadError, .forbidden)
        }
    }

    func testLoginCategoryForbidden() throws {
        let login = WebExtensionTestSeed.login(title: "Site", username: "u",
                                               password: "pw", website: "https://example.com")
        try WebExtensionTestSeed.insert(login, into: store, key: key)
        XCTAssertThrowsError(try WebExtensionReader.fillPayload(
            itemId: login.id, category: .login, store: store, key: key)) { error in
            XCTAssertEqual(error as? WebExtensionReader.ReadError, .forbidden)
        }
    }

    func testUnknownItemNotFound() {
        XCTAssertThrowsError(try WebExtensionReader.fillPayload(
            itemId: "missing", category: .identity, store: store, key: key)) { error in
            XCTAssertEqual(error as? WebExtensionReader.ReadError, .itemNotFound)
        }
    }

    // MARK: - Pure helpers

    func testSplitFullName() {
        XCTAssertEqual(WebExtensionReader.splitFullName("John Smith").given, "John")
        XCTAssertEqual(WebExtensionReader.splitFullName("John Smith").family, "Smith")
        XCTAssertEqual(WebExtensionReader.splitFullName("Mary Jane Smith").given, "Mary Jane")
        XCTAssertEqual(WebExtensionReader.splitFullName("Cher").given, "Cher")
        XCTAssertEqual(WebExtensionReader.splitFullName("Cher").family, "")
    }

    func testExpiryComponents() {
        XCTAssertEqual(WebExtensionReader.expiryComponents(from: "09/27")?.month, "09")
        XCTAssertEqual(WebExtensionReader.expiryComponents(from: "09/27")?.year4, "2027")
        XCTAssertEqual(WebExtensionReader.expiryComponents(from: "9-27")?.month, "09")
        XCTAssertEqual(WebExtensionReader.expiryComponents(from: "12/2030")?.year4, "2030")
        XCTAssertNil(WebExtensionReader.expiryComponents(from: "13/27"), "month must be 1-12")
        XCTAssertNil(WebExtensionReader.expiryComponents(from: "September 2027"))
        XCTAssertNil(WebExtensionReader.expiryComponents(from: ""))
    }

    // MARK: - Router authorization

    private func routerContext() -> WebExtensionRouterContext {
        let bytes = keyBytes
        let sharedStore = store!
        return WebExtensionRouterContext(retrieveKey: { bytes },
                                         makeStore: { sharedStore })
    }

    private func failingContext() -> WebExtensionRouterContext {
        let sharedStore = store!
        return WebExtensionRouterContext(
            retrieveKey: {
                XCTFail("rejected requests must never trigger an unlock")
                throw BiometricKeyStore.Failure.unavailable
            },
            makeStore: { sharedStore })
    }

    func testRouterGetFillPayloadHappyPath() async throws {
        let item = fullIdentity()
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "getFillPayload", "origin": "https://example.com",
             "itemId": item.id, "category": "identity"],
            context: routerContext())
        XCTAssertEqual(response["ok"] as? Bool, true)
        let data = try XCTUnwrap(response["data"] as? [String: Any])
        let values = try XCTUnwrap(data["values"] as? [String: String])
        XCTAssertEqual(values["email"], "me@example.com")
        XCTAssertEqual(data["category"] as? String, "identity")
        XCTAssertNotNil(data["expiresAt"] as? Int)
    }

    func testRouterGetFillPayloadReleasesCardNumberForCardFill() async throws {
        let item = fullCard()
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "getFillPayload", "origin": "https://shop.example.com",
             "itemId": item.id, "category": "card"],
            context: routerContext())
        let data = try XCTUnwrap(response["data"] as? [String: Any])
        let values = try XCTUnwrap(data["values"] as? [String: String])
        XCTAssertEqual(values["ccNumber"], "4111111111111111")
    }

    func testRouterRejectsNonHTTPSOriginBeforeUnlock() async {
        for origin in ["http://example.com", "about:blank", "", "javascript:alert(1)"] {
            let response = await WebExtensionRouter.route(
                ["v": 1, "cmd": "getFillPayload", "origin": origin,
                 "itemId": "x", "category": "identity"],
                context: failingContext())
            XCTAssertEqual(response["error"] as? String, "invalidOrigin", "origin: \(origin)")
        }
    }

    func testRouterRejectsMissingArgumentsBeforeUnlock() async {
        let noItem = await WebExtensionRouter.route(
            ["v": 1, "cmd": "getFillPayload", "origin": "https://example.com",
             "category": "identity"],
            context: failingContext())
        XCTAssertEqual(noItem["error"] as? String, "malformedMessage")

        let noCategory = await WebExtensionRouter.route(
            ["v": 1, "cmd": "getFillPayload", "origin": "https://example.com",
             "itemId": "x"],
            context: failingContext())
        XCTAssertEqual(noCategory["error"] as? String, "malformedMessage")
    }

    func testRouterRejectsNonFillableCategoriesBeforeUnlock() async {
        for category in ["login", "note", "sshKey", "recoveryCodes", "custom", "bogus"] {
            let response = await WebExtensionRouter.route(
                ["v": 1, "cmd": "getFillPayload", "origin": "https://example.com",
                 "itemId": "x", "category": category],
                context: failingContext())
            let error = response["error"] as? String
            XCTAssertTrue(error == "forbidden" || error == "malformedMessage",
                          "category \(category) must be rejected, got \(error ?? "ok")")
            XCTAssertNotEqual(response["ok"] as? Bool, true)
        }
    }

    func testRouterResponseCarriesNoUnrequestedSecrets() async throws {
        let identity = fullIdentity()
        let card = fullCard()
        try WebExtensionTestSeed.insert(identity, into: store, key: key)
        try WebExtensionTestSeed.insert(card, into: store, key: key)
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "getFillPayload", "origin": "https://example.com",
             "itemId": identity.id, "category": "identity"],
            context: routerContext())
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: response),
                                as: UTF8.self)
        XCTAssertFalse(serialized.contains("4111111111111111"),
                       "an identity fill must not carry card secrets")
        XCTAssertFalse(serialized.contains("ID-9999"),
                       "protected identity values must not cross the bridge")
    }
}
