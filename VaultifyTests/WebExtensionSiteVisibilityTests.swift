import XCTest
@testable import Vaultify

/// Per-site kill switch ("Hide on this site") for the Safari web extension:
/// storage semantics, the `siteSettings`/`setSiteHidden` commands, and the
/// fail-safe gating of every in-page surface (inline metadata list, save
/// gate, save write) while popup-driven fill stays available.
@MainActor
final class WebExtensionSiteVisibilityTests: XCTestCase {

    private var store: VaultStore!
    private var defaults: UserDefaults!
    private let suiteName = "WebExtensionSiteVisibilityTests"
    private let keyBytes = [UInt8](repeating: 5, count: 32)
    private var key: SecureBytes { SecureBytes(keyBytes) }

    override func setUp() {
        super.setUp()
        store = VaultStore(inMemory: true)
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func context() -> WebExtensionRouterContext {
        let bytes = keyBytes
        let sharedStore = store!
        let suite = defaults!
        return WebExtensionRouterContext(retrieveKey: { bytes },
                                         makeStore: { sharedStore },
                                         nativeSaveActive: { false },
                                         configDefaults: { suite })
    }

    /// Context asserting that a gated request never reaches the unlock or
    /// the session key — the hidden check must run strictly first.
    private func failingContext() -> WebExtensionRouterContext {
        let sharedStore = store!
        let suite = defaults!
        return WebExtensionRouterContext(
            retrieveKey: {
                XCTFail("hidden-site requests must never trigger an unlock")
                throw BiometricKeyStore.Failure.unavailable
            },
            makeStore: { sharedStore },
            retrieveSessionKey: {
                XCTFail("hidden-site requests must never touch the session key")
                return nil
            },
            nativeSaveActive: { false },
            configDefaults: { suite })
    }

    // MARK: - Storage semantics

    func testHiddenHostsRoundTripAndNormalization() {
        XCTAssertFalse(WebExtensionSaveGate.isHidden(host: "example.com", defaults: defaults))
        WebExtensionSaveGate.setHidden(host: "  EXAMPLE.com ", hidden: true, defaults: defaults)
        XCTAssertTrue(WebExtensionSaveGate.isHidden(host: "example.com", defaults: defaults))
        XCTAssertTrue(WebExtensionSaveGate.isHidden(host: "EXAMPLE.COM", defaults: defaults))
        // Hosts only, no bleed to lookalikes or subdomains.
        XCTAssertFalse(WebExtensionSaveGate.isHidden(host: "sub.example.com", defaults: defaults))
        XCTAssertFalse(WebExtensionSaveGate.isHidden(host: "evilexample.com", defaults: defaults))
        WebExtensionSaveGate.setHidden(host: "example.com", hidden: false, defaults: defaults)
        XCTAssertFalse(WebExtensionSaveGate.isHidden(host: "example.com", defaults: defaults))
        XCTAssertEqual(WebExtensionSaveGate.hiddenHosts(defaults: defaults), [])
    }

    func testSetHiddenIsIdempotent() {
        WebExtensionSaveGate.setHidden(host: "a.com", hidden: true, defaults: defaults)
        WebExtensionSaveGate.setHidden(host: "a.com", hidden: true, defaults: defaults)
        XCTAssertEqual(WebExtensionSaveGate.hiddenHosts(defaults: defaults), ["a.com"])
        WebExtensionSaveGate.setHidden(host: "a.com", hidden: false, defaults: defaults)
        WebExtensionSaveGate.setHidden(host: "a.com", hidden: false, defaults: defaults)
        XCTAssertEqual(WebExtensionSaveGate.hiddenHosts(defaults: defaults), [])
    }

    // MARK: - siteSettings / setSiteHidden commands

    func testSiteSettingsReportsHiddenFlag() async throws {
        var response = await WebExtensionRouter.route(
            ["cmd": "siteSettings", "v": 1, "origin": "https://example.com"],
            context: failingContext())
        var data = try XCTUnwrap(response["data"] as? [String: Any])
        XCTAssertEqual(data["hidden"] as? Bool, false)

        WebExtensionSaveGate.setHidden(host: "example.com", hidden: true, defaults: defaults)
        response = await WebExtensionRouter.route(
            ["cmd": "siteSettings", "v": 1, "origin": "https://example.com"],
            context: failingContext())
        data = try XCTUnwrap(response["data"] as? [String: Any])
        XCTAssertEqual(data["hidden"] as? Bool, true)
    }

    func testSetSiteHiddenStoresAndUnhides() async {
        var response = await WebExtensionRouter.route(
            ["cmd": "setSiteHidden", "v": 1, "origin": "https://Example.com", "hidden": true],
            context: failingContext())
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertTrue(WebExtensionSaveGate.isHidden(host: "example.com", defaults: defaults))

        response = await WebExtensionRouter.route(
            ["cmd": "setSiteHidden", "v": 1, "origin": "https://example.com", "hidden": false],
            context: failingContext())
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertFalse(WebExtensionSaveGate.isHidden(host: "example.com", defaults: defaults))
    }

    func testSetSiteHiddenRequiresExplicitFlagAndValidOrigin() async {
        var response = await WebExtensionRouter.route(
            ["cmd": "setSiteHidden", "v": 1, "origin": "https://example.com"],
            context: failingContext())
        XCTAssertEqual(response["error"] as? String, "malformedMessage")

        response = await WebExtensionRouter.route(
            ["cmd": "setSiteHidden", "v": 1, "origin": "http://example.com", "hidden": true],
            context: failingContext())
        XCTAssertEqual(response["error"] as? String, "invalidOrigin")
    }

    // MARK: - Fail-safe gating of in-page surfaces

    func testHiddenHostGetsNoInlineListBeforeAnySessionAccess() async {
        WebExtensionSaveGate.setHidden(host: "example.com", hidden: true, defaults: defaults)
        // failingContext asserts the session key is never touched.
        let response = await WebExtensionRouter.route(
            ["cmd": "listItemsSession", "v": 1, "origin": "https://example.com"],
            context: failingContext())
        XCTAssertEqual(response["error"] as? String, "hiddenSite")
    }

    func testSaveGateRefusesHiddenHost() async throws {
        WebExtensionSaveGate.setHidden(host: "example.com", hidden: true, defaults: defaults)
        let response = await WebExtensionRouter.route(
            ["cmd": "saveGate", "v": 1, "origin": "https://example.com"],
            context: failingContext())
        let data = try XCTUnwrap(response["data"] as? [String: Any])
        XCTAssertEqual(data["offer"] as? Bool, false)
    }

    func testSaveLoginRefusedForHiddenHostBeforeUnlock() async {
        WebExtensionSaveGate.setHidden(host: "example.com", hidden: true, defaults: defaults)
        let response = await WebExtensionRouter.route(
            ["cmd": "saveLogin", "v": 1, "origin": "https://example.com",
             "username": "alice", "password": "pw-secret-1", "title": ""],
            context: failingContext())
        XCTAssertEqual(response["error"] as? String, "forbidden")
    }

    // MARK: - Popup surfaces stay available

    func testPopupListAndFillUnaffectedByHiddenHost() async throws {
        WebExtensionSaveGate.setHidden(host: "example.com", hidden: true, defaults: defaults)
        let item = WebExtensionTestSeed.login(title: "Example",
                                              username: "alice",
                                              password: "pw-secret-1",
                                              website: "https://example.com")
        try WebExtensionTestSeed.insert(item, into: store, key: key)

        // The popup list still serves the hidden host (explicit user surface).
        let list = await WebExtensionRouter.route(
            ["cmd": "listItems", "v": 1, "origin": "https://example.com"],
            context: context())
        XCTAssertEqual(list["ok"] as? Bool, true)
        let data = try XCTUnwrap(list["data"] as? [String: Any])
        let logins = try XCTUnwrap(data["logins"] as? [[String: Any]])
        XCTAssertEqual(logins.count, 1)

        // getFillPayload reaches the vault (itemNotFound, not a hidden gate).
        let fill = await WebExtensionRouter.route(
            ["cmd": "getFillPayload", "v": 1, "origin": "https://example.com",
             "itemId": "missing-item", "category": "identity"],
            context: context())
        XCTAssertEqual(fill["error"] as? String, "itemNotFound")
    }
}
