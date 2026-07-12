import XCTest
@testable import Vaultify

/// Shared seeding helper for the web-extension read-path tests: seals a
/// `VaultItem` exactly like the app's write path and inserts the record into
/// an in-memory store. Reused by `SafariMessageRouterTests`.
@MainActor
enum WebExtensionTestSeed {
    static func insert(_ item: VaultItem, into store: VaultStore, key: SecureBytes,
                       archived: Bool = false, trashedAt: Date? = nil) throws {
        let sealed = try AESGCM.seal(JSONEncoder().encode(item.secret), key: key)
        let record = ItemRecord(id: item.id, sealed: sealed, trashedAt: trashedAt)
        record.archived = archived
        store.context.insert(record)
        try store.context.save()
    }

    static func login(id: String = UUID().uuidString, title: String,
                      username: String, password: String, website: String) -> VaultItem {
        VaultItem(id: id, category: .login, title: title, fields: [
            DynamicField(label: "Username", kind: .username, value: username),
            DynamicField(label: "Password", kind: .password, value: password, protected: true),
            DynamicField(label: "Website", kind: .url, value: website),
        ])
    }

    static func identity(id: String = UUID().uuidString, title: String,
                         email: String) -> VaultItem {
        VaultItem(id: id, category: .identity, title: title, fields: [
            DynamicField(label: "Full Name", kind: .text, value: title),
            DynamicField(label: "Email", kind: .email, value: email),
        ])
    }

    static func card(id: String = UUID().uuidString, title: String,
                     number: String, cvv: String = "123") -> VaultItem {
        VaultItem(id: id, category: .card, title: title, fields: [
            DynamicField(label: "Cardholder", kind: .text, value: "Holder"),
            DynamicField(label: "Card Number", kind: .monospace, value: number, protected: true),
            DynamicField(label: "Security Code", kind: .monospace, value: cvv, protected: true),
        ])
    }
}

@MainActor
final class WebExtensionReaderTests: XCTestCase {

    private var store: VaultStore!
    private let key = SecureBytes(Array(repeating: 7, count: 32))

    override func setUp() {
        super.setUp()
        store = VaultStore(inMemory: true)
    }

    // MARK: - Origin-scoped logins

    func testLoginsScopedToHost() throws {
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.login(title: "Example", username: "alice",
                                       password: "pw-1", website: "https://example.com"),
            into: store, key: key)
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.login(title: "Other", username: "bob",
                                       password: "pw-2", website: "https://other.net"),
            into: store, key: key)

        let lists = WebExtensionReader.itemsMatching(host: "example.com", store: store, key: key)
        XCTAssertEqual(lists.logins.map(\.title), ["Example"])
        XCTAssertEqual(lists.logins.first?.username, "alice")
    }

    func testSubdomainMatchingBothDirections() throws {
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.login(title: "App", username: "a",
                                       password: "p", website: "https://app.example.com"),
            into: store, key: key)
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.login(title: "Root", username: "r",
                                       password: "p", website: "https://example.com"),
            into: store, key: key)

        // Origin at the registrable domain matches a subdomain login and vice versa.
        let atRoot = WebExtensionReader.itemsMatching(host: "example.com", store: store, key: key)
        XCTAssertEqual(Set(atRoot.logins.map(\.title)), ["App", "Root"])
        let atSub = WebExtensionReader.itemsMatching(host: "login.example.com", store: store, key: key)
        XCTAssertTrue(atSub.logins.map(\.title).contains("Root"))
    }

    func testTrashedAndArchivedExcluded() throws {
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.login(title: "Trashed", username: "t",
                                       password: "p", website: "https://example.com"),
            into: store, key: key, trashedAt: .now)
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.login(title: "Archived", username: "a",
                                       password: "p", website: "https://example.com"),
            into: store, key: key, archived: true)

        let lists = WebExtensionReader.itemsMatching(host: "example.com", store: store, key: key)
        XCTAssertTrue(lists.logins.isEmpty)
    }

    // MARK: - Cards masked to last-4

    func testCardMaskedToLast4WithBrand() throws {
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.card(title: "Main Card", number: "4111111111111111"),
            into: store, key: key)

        let lists = WebExtensionReader.itemsMatching(host: "example.com", store: store, key: key)
        let card = try XCTUnwrap(lists.cards.first)
        XCTAssertEqual(card.brand, "VISA")
        XCTAssertEqual(card.last4, "1111")
        XCTAssertEqual(card.last4.count, 4, "only the last four digits may surface")
        XCTAssertFalse(card.title.contains("4111111111111111"))
    }

    func testSecurityCodeNeverMistakenForCardNumber() throws {
        // A card whose only monospace fields are short codes must not surface
        // any digits as "last-4" (Amex CIDs are 4 digits — a naive fallback
        // would leak them).
        let item = VaultItem(category: .card, title: "Code Only", fields: [
            DynamicField(label: "Security Code", kind: .monospace, value: "1234", protected: true),
        ])
        try WebExtensionTestSeed.insert(item, into: store, key: key)

        let lists = WebExtensionReader.itemsMatching(host: "example.com", store: store, key: key)
        XCTAssertEqual(lists.cards.first?.last4, "")
        XCTAssertEqual(lists.cards.first?.brand, "")
    }

    func testSecretGuardSealedNumberYieldsNoLast4() throws {
        // A SecretGuard payload is tagged base64; digit-stripping it would
        // surface ciphertext digits as brand/last-4. The raw value must be
        // rejected before any digit extraction (guard2 deliberately unset).
        let item = VaultItem(category: .card, title: "Sealed", fields: [
            DynamicField(label: "Card Number", kind: .monospace,
                         value: "v2g:99887766554433221100AAAA", protected: true),
        ])
        try WebExtensionTestSeed.insert(item, into: store, key: key)

        let lists = WebExtensionReader.itemsMatching(host: "example.com", store: store, key: key)
        XCTAssertEqual(lists.cards.first?.last4, "")
        XCTAssertEqual(lists.cards.first?.brand, "")
    }

    // MARK: - Identities are metadata only

    func testIdentityListedGloballyWithTitleOnly() throws {
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.identity(title: "Me", email: "me@example.com"),
            into: store, key: key)

        let lists = WebExtensionReader.itemsMatching(host: "unrelated.net", store: store, key: key)
        XCTAssertEqual(lists.identities.map(\.title), ["Me"])
    }

    // MARK: - copyableValue whitelist

    func testCopyUsernameAllowed() throws {
        let item = WebExtensionTestSeed.login(title: "Example", username: "alice",
                                              password: "pw", website: "https://example.com")
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let value = try WebExtensionReader.copyableValue(itemId: item.id, kind: .username,
                                                         store: store, key: key)
        XCTAssertEqual(value, "alice")
    }

    func testCopyIdentityEmailAllowed() throws {
        let item = WebExtensionTestSeed.identity(title: "Me", email: "me@example.com")
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let value = try WebExtensionReader.copyableValue(itemId: item.id, kind: .email,
                                                         store: store, key: key)
        XCTAssertEqual(value, "me@example.com")
    }

    func testCopySecretKindForbidden() throws {
        let item = WebExtensionTestSeed.login(title: "Example", username: "alice",
                                              password: "pw", website: "https://example.com")
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        XCTAssertThrowsError(try WebExtensionReader.copyableValue(
            itemId: item.id, kind: .password, store: store, key: key)) { error in
            XCTAssertEqual(error as? WebExtensionReader.ReadError, .forbidden)
        }
    }

    func testCopyProtectedFieldForbiddenEvenForWhitelistedKind() throws {
        let item = VaultItem(category: .custom, title: "Guarded", fields: [
            DynamicField(label: "Secret Note", kind: .text, value: "hidden", protected: true),
        ])
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        XCTAssertThrowsError(try WebExtensionReader.copyableValue(
            itemId: item.id, kind: .text, store: store, key: key)) { error in
            XCTAssertEqual(error as? WebExtensionReader.ReadError, .forbidden)
        }
    }

    func testCopyUnknownItemNotFound() {
        XCTAssertThrowsError(try WebExtensionReader.copyableValue(
            itemId: "missing", kind: .username, store: store, key: key)) { error in
            XCTAssertEqual(error as? WebExtensionReader.ReadError, .itemNotFound)
        }
    }
}
