import XCTest
@testable import Vaultify

/// Router tests for the Safari extension's signup-assist commands:
/// `saveLogin` (authorization, origin binding, duplicate handling, the
/// native-save/never-save suppression belt), `generatePassword` (shape +
/// rate limit), and `saveGate`/`neverSave` (overlay gating). All rejections
/// are verified to happen BEFORE any unlock, so a forged request can never
/// trigger Face ID.
@MainActor
final class WebExtensionSaveLoginTests: XCTestCase {

    private var store: VaultStore!
    private var defaults: UserDefaults!
    private let suiteName = "WebExtensionSaveLoginTests"
    private let keyBytes = [UInt8](repeating: 9, count: 32)
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

    private func context(nativeSave: Bool = false) -> WebExtensionRouterContext {
        let bytes = keyBytes
        let sharedStore = store!
        let suite = defaults!
        return WebExtensionRouterContext(retrieveKey: { bytes },
                                         makeStore: { sharedStore },
                                         nativeSaveActive: { nativeSave },
                                         configDefaults: { suite })
    }

    private func failingContext(nativeSave: Bool = false) -> WebExtensionRouterContext {
        let sharedStore = store!
        let suite = defaults!
        return WebExtensionRouterContext(
            retrieveKey: {
                XCTFail("rejected requests must never trigger an unlock")
                throw BiometricKeyStore.Failure.unavailable
            },
            makeStore: { sharedStore },
            nativeSaveActive: { nativeSave },
            configDefaults: { suite })
    }

    private func saveRequest(origin: String = "https://example.com",
                             username: String = "alice",
                             password: String = "pw-secret-1",
                             title: String = "") -> [String: Any] {
        ["v": 1, "cmd": "saveLogin", "origin": origin,
         "username": username, "password": password, "title": title]
    }

    // MARK: - saveLogin happy path

    func testSaveLoginCreatesLoginServedBackForHost() async throws {
        let response = await WebExtensionRouter.route(saveRequest(), context: context())
        XCTAssertEqual(response["ok"] as? Bool, true)
        let data = try XCTUnwrap(response["data"] as? [String: Any])
        let itemId = try XCTUnwrap(data["itemId"] as? String)
        XCTAssertFalse(itemId.isEmpty)

        let lists = WebExtensionReader.itemsMatching(host: "example.com",
                                                     store: store, key: key)
        XCTAssertEqual(lists.logins.map(\.username), ["alice"])
        XCTAssertEqual(lists.logins.first?.title, "example.com",
                       "blank title falls back to the derived site title")
    }

    func testSaveLoginHonorsEditedTitle() async throws {
        let response = await WebExtensionRouter.route(
            saveRequest(title: "Work account"), context: context())
        XCTAssertEqual(response["ok"] as? Bool, true)
        let lists = WebExtensionReader.itemsMatching(host: "example.com",
                                                     store: store, key: key)
        XCTAssertEqual(lists.logins.first?.title, "Work account")
    }

    // MARK: - saveLogin duplicate handling

    func testSaveLoginDuplicateHostAndUsernameRejected() async throws {
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.login(title: "Example", username: "Alice",
                                       password: "old-pw", website: "https://example.com"),
            into: store, key: key)
        // Case-insensitive on the username; same host via origin.
        let response = await WebExtensionRouter.route(
            saveRequest(username: "alice"), context: context())
        XCTAssertEqual(response["error"] as? String, "duplicate")
    }

    func testSaveLoginDifferentUsernameOnSameHostSaves() async throws {
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.login(title: "Example", username: "alice",
                                       password: "old-pw", website: "https://example.com"),
            into: store, key: key)
        let response = await WebExtensionRouter.route(
            saveRequest(username: "bob"), context: context())
        XCTAssertEqual(response["ok"] as? Bool, true)
    }

    // MARK: - saveLogin rejections (all before unlock)

    func testSaveLoginRejectsNonHTTPSOriginBeforeUnlock() async {
        for origin in ["http://example.com", "", "about:blank", "javascript:alert(1)"] {
            let response = await WebExtensionRouter.route(
                saveRequest(origin: origin), context: failingContext())
            XCTAssertEqual(response["error"] as? String, "invalidOrigin",
                           "origin: \(origin)")
        }
    }

    func testSaveLoginRejectsMissingOrOversizedFieldsBeforeUnlock() async {
        let noPassword = await WebExtensionRouter.route(
            saveRequest(password: ""), context: failingContext())
        XCTAssertEqual(noPassword["error"] as? String, "malformedMessage")

        let hugePassword = await WebExtensionRouter.route(
            saveRequest(password: String(repeating: "x", count: 600)),
            context: failingContext())
        XCTAssertEqual(hugePassword["error"] as? String, "malformedMessage")

        let hugeTitle = await WebExtensionRouter.route(
            saveRequest(title: String(repeating: "t", count: 200)),
            context: failingContext())
        XCTAssertEqual(hugeTitle["error"] as? String, "malformedMessage")
    }

    func testSaveLoginRefusedWhenNativeSaveSheetOwnsTheFlow() async {
        let response = await WebExtensionRouter.route(
            saveRequest(), context: failingContext(nativeSave: true))
        XCTAssertEqual(response["error"] as? String, "forbidden",
                       "no extension save while the OS-native sheet is active")
    }

    func testSaveLoginTrimsUsernameBeforeDuplicateCompare() async throws {
        try WebExtensionTestSeed.insert(
            WebExtensionTestSeed.login(title: "Example", username: "alice",
                                       password: "old-pw", website: "https://example.com"),
            into: store, key: key)
        let response = await WebExtensionRouter.route(
            saveRequest(username: "  alice "), context: context())
        XCTAssertEqual(response["error"] as? String, "duplicate",
                       "surrounding whitespace must not defeat the duplicate check")
    }

    func testSaveLoginRefusedForNeverSavedHost() async {
        WebExtensionSaveGate.addNeverSave(host: "example.com", defaults: defaults)
        let response = await WebExtensionRouter.route(
            saveRequest(), context: failingContext())
        XCTAssertEqual(response["error"] as? String, "forbidden")
    }

    // MARK: - saveLogin rate limit

    func testSaveLoginRateLimitedPerHostBeforeUnlock() async {
        for index in 0..<WebExtensionSaveGate.saveLimit {
            let response = await WebExtensionRouter.route(
                saveRequest(username: "user\(index)"), context: context())
            XCTAssertEqual(response["ok"] as? Bool, true, "save \(index) within limit")
        }
        // Refused BEFORE any unlock — spamming can neither prompt-bomb Face
        // ID nor probe usernames via the duplicate error past the window.
        let limited = await WebExtensionRouter.route(
            saveRequest(username: "user0"), context: failingContext())
        XCTAssertEqual(limited["error"] as? String, "rateLimited")

        // A different host keeps its own independent window.
        let otherHost = await WebExtensionRouter.route(
            saveRequest(origin: "https://other.example", username: "alice"),
            context: context())
        XCTAssertEqual(otherHost["ok"] as? Bool, true)
    }

    func testSaveRateLimitWindowSlidesAndIsolatesHosts() {
        let now = Date()
        for _ in 0..<WebExtensionSaveGate.saveLimit {
            XCTAssertTrue(WebExtensionSaveGate.allowSave(host: "example.com", now: now,
                                                         defaults: defaults))
        }
        XCTAssertFalse(WebExtensionSaveGate.allowSave(host: "example.com", now: now,
                                                      defaults: defaults))
        XCTAssertTrue(WebExtensionSaveGate.allowSave(host: "other.example", now: now,
                                                     defaults: defaults),
                      "hosts are limited independently")
        let later = now.addingTimeInterval(WebExtensionSaveGate.saveWindow + 1)
        XCTAssertTrue(WebExtensionSaveGate.allowSave(host: "example.com", now: later,
                                                     defaults: defaults),
                      "window expiry re-admits saves")
    }

    // MARK: - saveGate + neverSave

    func testSaveGateOffersOnlyWithoutNativeSaveAndOptOut() async {
        let request: [String: Any] = ["v": 1, "cmd": "saveGate",
                                      "origin": "https://example.com"]

        let open = await WebExtensionRouter.route(request, context: failingContext())
        XCTAssertEqual((open["data"] as? [String: Any])?["offer"] as? Bool, true)

        let nativeOwned = await WebExtensionRouter.route(
            request, context: failingContext(nativeSave: true))
        XCTAssertEqual((nativeOwned["data"] as? [String: Any])?["offer"] as? Bool, false)

        let stored = await WebExtensionRouter.route(
            ["v": 1, "cmd": "neverSave", "origin": "https://EXAMPLE.com"],
            context: failingContext())
        XCTAssertEqual(stored["ok"] as? Bool, true)

        let optedOut = await WebExtensionRouter.route(request, context: failingContext())
        XCTAssertEqual((optedOut["data"] as? [String: Any])?["offer"] as? Bool, false,
                       "never-save must hold immediately, case-insensitively")
    }

    func testSaveGateRejectsNonHTTPSOrigin() async {
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "saveGate", "origin": "http://example.com"],
            context: failingContext())
        XCTAssertEqual(response["error"] as? String, "invalidOrigin")
    }

    // MARK: - generatePassword

    func testGeneratePasswordDefaultShape() async throws {
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "generatePassword"], context: failingContext())
        XCTAssertEqual(response["ok"] as? Bool, true)
        let data = try XCTUnwrap(response["data"] as? [String: Any])
        let password = try XCTUnwrap(data["password"] as? String)
        XCTAssertEqual(password.count, 20, "default generation length")
    }

    func testGeneratePasswordHonorsBoundedLength() async throws {
        let response = await WebExtensionRouter.route(
            ["v": 1, "cmd": "generatePassword", "length": 32],
            context: failingContext())
        let data = try XCTUnwrap(response["data"] as? [String: Any])
        XCTAssertEqual((data["password"] as? String)?.count, 32)

        let tooShort = await WebExtensionRouter.route(
            ["v": 1, "cmd": "generatePassword", "length": 4],
            context: failingContext())
        XCTAssertEqual(tooShort["error"] as? String, "malformedMessage")

        let tooLong = await WebExtensionRouter.route(
            ["v": 1, "cmd": "generatePassword", "length": 500],
            context: failingContext())
        XCTAssertEqual(tooLong["error"] as? String, "malformedMessage")
    }

    func testGeneratePasswordRateLimited() async {
        for index in 0..<WebExtensionSaveGate.generateLimit {
            let response = await WebExtensionRouter.route(
                ["v": 1, "cmd": "generatePassword"], context: failingContext())
            XCTAssertEqual(response["ok"] as? Bool, true, "request \(index) within limit")
        }
        let limited = await WebExtensionRouter.route(
            ["v": 1, "cmd": "generatePassword"], context: failingContext())
        XCTAssertEqual(limited["error"] as? String, "rateLimited")
    }

    func testGenerateRateLimitWindowSlides() {
        let now = Date()
        for _ in 0..<WebExtensionSaveGate.generateLimit {
            XCTAssertTrue(WebExtensionSaveGate.allowGenerate(now: now, defaults: defaults))
        }
        XCTAssertFalse(WebExtensionSaveGate.allowGenerate(now: now, defaults: defaults))
        let later = now.addingTimeInterval(WebExtensionSaveGate.generateWindow + 1)
        XCTAssertTrue(WebExtensionSaveGate.allowGenerate(now: later, defaults: defaults),
                      "window expiry re-admits generation")
    }

    // MARK: - status capabilities

    func testStatusCarriesNativeSaveCapability() async throws {
        let off = await WebExtensionRouter.route(
            ["v": 1, "cmd": "status"], context: failingContext(nativeSave: false))
        let offCaps = try XCTUnwrap(
            (off["data"] as? [String: Any])?["capabilities"] as? [String: Any])
        XCTAssertEqual(offCaps["nativeSave"] as? Bool, false)

        let on = await WebExtensionRouter.route(
            ["v": 1, "cmd": "status"], context: failingContext(nativeSave: true))
        let onCaps = try XCTUnwrap(
            (on["data"] as? [String: Any])?["capabilities"] as? [String: Any])
        XCTAssertEqual(onCaps["nativeSave"] as? Bool, true)
    }

    // MARK: - Response hygiene

    func testSaveLoginResponseNeverEchoesThePassword() async throws {
        let response = await WebExtensionRouter.route(
            saveRequest(password: "pw-canary-777"), context: context())
        let serialized = String(decoding: try JSONSerialization.data(withJSONObject: response),
                                as: UTF8.self)
        XCTAssertFalse(serialized.contains("pw-canary-777"),
                       "the saved password must never come back over the bridge")
    }
}
