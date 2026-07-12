import XCTest
@testable import Vaultify

/// Routing tests for the Safari web extension's native-messaging protocol
/// (`WebExtensionRouter`), with an injected fixed key and in-memory store —
/// the appex's `SafariMessageRouter` binds the same router to Face ID and the
/// shared on-disk store.
@MainActor
final class SafariMessageRouterTests: XCTestCase {

    private final class UnlockCounter: @unchecked Sendable {
        var count = 0
    }

    private var store: VaultStore!
    private var unlocks: UnlockCounter!
    private let keyBytes = [UInt8](repeating: 7, count: 32)
    private var key: SecureBytes { SecureBytes(keyBytes) }

    override func setUp() {
        super.setUp()
        store = VaultStore(inMemory: true)
        unlocks = UnlockCounter()
    }

    private func context(retrieveError: Error? = nil) -> WebExtensionRouterContext {
        let counter = unlocks!
        let bytes = keyBytes
        let sharedStore = store!
        return WebExtensionRouterContext(
            retrieveKey: {
                counter.count += 1
                if let retrieveError { throw retrieveError }
                return bytes
            },
            makeStore: { sharedStore })
    }

    private func json(of response: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: response)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Envelope

    func testEchoRoundTrip() async {
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "echo", "payload": "hello"], context: context())
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual((response["data"] as? [String: Any])?["echo"] as? String, "hello")
        XCTAssertEqual(response["v"] as? Int, 1)
    }

    func testMissingVersionRejected() async {
        let response = await WebExtensionRouter.route(["cmd": "echo"], context: context())
        XCTAssertEqual(response["error"] as? String, "unsupportedVersion")
    }

    func testFutureVersionRejected() async {
        let response = await WebExtensionRouter.route(["v": 2, "cmd": "status"], context: context())
        XCTAssertEqual(response["error"] as? String, "unsupportedVersion")
    }

    func testUnknownCommandRejected() async {
        let response = await WebExtensionRouter.route(["v": 1, "cmd": "dumpVault"], context: context())
        XCTAssertEqual(response["error"] as? String, "unknownCommand")
    }

    func testMalformedMessageRejected() async {
        let nilResponse = await WebExtensionRouter.route(nil, context: context())
        XCTAssertEqual(nilResponse["error"] as? String, "malformedMessage")
        let stringResponse = await WebExtensionRouter.route("listItems", context: context())
        XCTAssertEqual(stringResponse["error"] as? String, "malformedMessage")
    }

    // MARK: - status

    func testStatusAlwaysLockedAndNeverUnlocks() async {
        let response = await WebExtensionRouter.route(["v": 1, "cmd": "status"], context: context())
        XCTAssertEqual((response["data"] as? [String: Any])?["locked"] as? Bool, true)
        XCTAssertEqual(unlocks.count, 0, "status must not trigger a key retrieval")
    }

    // MARK: - listItems

    func testListItemsRejectsNonHTTPSOriginBeforeUnlock() async {
        for origin in ["http://example.com", "about:blank", "javascript:alert(1)", ""] {
            let response = await WebExtensionRouter.route(
                ["v": 1, "cmd": "listItems", "origin": origin], context: context())
            XCTAssertEqual(response["error"] as? String, "invalidOrigin", "origin: \(origin)")
        }
        XCTAssertEqual(unlocks.count, 0, "invalid origins must not trigger Face ID")
    }

    func testListItemsReturnsOriginScopedMetadataOnly() async throws {
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.login(title: "Example", username: "alice",
                                       password: "sup3r-secret", website: "https://example.com"),
            into: store, key: key)
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.identity(title: "Me", email: "me@example.com"),
            into: store, key: key)
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.card(title: "Main Card", number: "4111111111111111"),
            into: store, key: key)

        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "listItems", "origin": "https://example.com"], context: context())

        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(unlocks.count, 1)
        let data = try XCTUnwrap(response["data"] as? [String: Any])
        let logins = try XCTUnwrap(data["logins"] as? [[String: Any]])
        XCTAssertEqual(logins.first?["username"] as? String, "alice")

        // The serialized response must carry no secret material.
        let serialized = try json(of: response)
        XCTAssertFalse(serialized.contains("sup3r-secret"), "password leaked over the bridge")
        XCTAssertFalse(serialized.contains("4111111111111111"), "full card number leaked")
        XCTAssertFalse(serialized.contains("me@example.com"),
                       "identity field values must not appear in list metadata")
        XCTAssertTrue(serialized.contains("1111"), "masked last-4 expected")
    }

    func testListItemsUnlockCancelledMapped() async {
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "listItems", "origin": "https://example.com"],
            context: context(retrieveError: BiometricKeyStore.Failure.cancelled))
        XCTAssertEqual(response["error"] as? String, "unlockCancelled")
    }

    func testListItemsUnlockFailureMapped() async {
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "listItems", "origin": "https://example.com"],
            context: context(retrieveError: BiometricKeyStore.Failure.unavailable))
        XCTAssertEqual(response["error"] as? String, "unlockFailed")
    }

    // MARK: - copyValue

    func testCopyValueReturnsWhitelistedField() async throws {
        let item = WebExtensionTestSeed.login(title: "Example", username: "alice",
                                              password: "pw", website: "https://example.com")
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "copyValue", "itemId": item.id, "fieldKind": "username"],
            context: context())
        XCTAssertEqual((response["data"] as? [String: Any])?["value"] as? String, "alice")
    }

    func testCopyValueSecretKindForbiddenWithoutUnlock() async throws {
        let item = WebExtensionTestSeed.login(title: "Example", username: "alice",
                                              password: "pw", website: "https://example.com")
        try WebExtensionTestSeed.insert(item, into: store, key: key)
        for kind in ["password", "totp", "monospace", "number", "bogus"] {
            let response = await WebExtensionRouter.route(
                ["v": 1, "cmd": "copyValue", "itemId": item.id, "fieldKind": kind],
                context: context())
            XCTAssertEqual(response["error"] as? String, "forbidden", "kind: \(kind)")
        }
        XCTAssertEqual(unlocks.count, 0, "forbidden kinds must be rejected before Face ID")
    }

    func testCopyValueUnknownItemNotFound() async {
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "copyValue", "itemId": "missing", "fieldKind": "username"],
            context: context())
        XCTAssertEqual(response["error"] as? String, "itemNotFound")
    }

    func testCopyValueMissingArgumentsMalformed() async {
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "copyValue"], context: context())
        XCTAssertEqual(response["error"] as? String, "malformedMessage")
    }

    // MARK: - Origin parsing

    func testHTTPSHostParsing() {
        XCTAssertEqual(WebExtensionRouter.httpsHost(fromOrigin: "https://Example.COM"), "example.com")
        XCTAssertEqual(WebExtensionRouter.httpsHost(fromOrigin: "https://app.example.com"), "app.example.com")
        XCTAssertNil(WebExtensionRouter.httpsHost(fromOrigin: "http://example.com"))
        XCTAssertNil(WebExtensionRouter.httpsHost(fromOrigin: "file:///etc/passwd"))
        XCTAssertNil(WebExtensionRouter.httpsHost(fromOrigin: nil))
        XCTAssertNil(WebExtensionRouter.httpsHost(fromOrigin: "https://"))
    }
}
