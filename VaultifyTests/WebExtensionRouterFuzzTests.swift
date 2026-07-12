import XCTest
@testable import Vaultify

/// Protocol fuzz for the Safari web extension's native router: structurally
/// malformed messages, version mismatches, oversized payloads, hostile origin
/// strings, and a serialized-response sweep asserting that no command besides
/// `getFillPayload` can ever carry a vault field value. Every rejection is
/// asserted to happen BEFORE any unlock, so fuzzed input can never trigger
/// Face ID.
@MainActor
final class WebExtensionRouterFuzzTests: XCTestCase {

    private var store: VaultStore!
    private var defaults: UserDefaults!
    private let suiteName = "WebExtensionRouterFuzzTests"
    private let keyBytes = [UInt8](repeating: 7, count: 32)
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

    /// Context whose unlock path fails the test — fuzzed input must be
    /// rejected before any key retrieval.
    private func failingContext() -> WebExtensionRouterContext {
        let sharedStore = store!
        let suite = defaults!
        return WebExtensionRouterContext(
            retrieveKey: {
                XCTFail("fuzzed requests must never trigger an unlock")
                throw BiometricKeyStore.Failure.unavailable
            },
            makeStore: { sharedStore },
            retrieveSessionKey: {
                XCTFail("fuzzed requests must never touch the session key")
                return nil
            },
            nativeSaveActive: { false },
            configDefaults: { suite })
    }

    private func liveContext() -> WebExtensionRouterContext {
        let bytes = keyBytes
        let sharedStore = store!
        let suite = defaults!
        return WebExtensionRouterContext(retrieveKey: { bytes },
                                         makeStore: { sharedStore },
                                         nativeSaveActive: { false },
                                         configDefaults: { suite })
    }

    private func routeError(_ raw: Any?) async -> String? {
        let response = await WebExtensionRouter.route(raw, context: failingContext())
        XCTAssertEqual(response["ok"] as? Bool, false)
        return response["error"] as? String
    }

    // MARK: - Structural fuzz

    func testMalformedShapesRejected() async {
        let shapes: [Any?] = [
            nil,
            "just a string",
            [1, 2, 3],
            ["v": 1],                       // no cmd
            ["cmd": 42, "v": 1],            // cmd not a string
            ["cmd": NSNull(), "v": 1],
        ]
        for raw in shapes {
            let error = await routeError(raw)
            XCTAssertEqual(error, "malformedMessage", "shape: \(String(describing: raw))")
        }
    }

    func testVersionGateRejectsAnythingButV1() async {
        let versions: [Any] = [0, 2, -1, "1", 1.5]
        for version in versions {
            let error = await routeError(["cmd": "status", "v": version])
            XCTAssertEqual(error, "unsupportedVersion", "v: \(version)")
        }
        // Missing version parses as 0 → unsupported.
        let missing = await routeError(["cmd": "status"])
        XCTAssertEqual(missing, "unsupportedVersion")
    }

    func testUnknownCommandRejected() async {
        for cmd in ["getVaultKey", "listAll", "exportVault", ""] {
            let error = await routeError(["cmd": cmd, "v": 1])
            XCTAssertEqual(error, "unknownCommand", "cmd: \(cmd)")
        }
    }

    func testOversizedEchoPayloadBounded() async {
        let megabyte = String(repeating: "A", count: 1_048_576)
        let response = await WebExtensionRouter.route(
            ["cmd": "echo", "v": 1, "payload": megabyte],
            context: failingContext())
        XCTAssertEqual(response["ok"] as? Bool, true)
        let data = response["data"] as? [String: Any]
        let echoed = data?["echo"] as? String ?? ""
        XCTAssertEqual(echoed.count, 512, "echo reflection must stay bounded")
    }

    // MARK: - Origin fuzz

    func testHostileOriginsRejectedBeforeAnyVaultAccess() async {
        let origins = [
            "http://example.com",
            "",
            "https://",
            "javascript:alert(1)",
            "file:///etc/passwd",
            "ftp://example.com",
            "https://:443",
        ]
        for origin in origins {
            for cmd in ["listItems", "listItemsSession", "saveGate",
                        "siteSettings", "setSiteHidden", "neverSave"] {
                let error = await routeError(
                    ["cmd": cmd, "v": 1, "origin": origin, "hidden": true])
                XCTAssertEqual(error, "invalidOrigin", "cmd: \(cmd) origin: \(origin)")
            }
        }
    }

    func testUnicodeHostNeverBecomesItsASCIILookalike() {
        // Matching operates on the exact (lowercased) host string. Whatever a
        // Unicode confusable origin parses to, it must never equal the ASCII
        // site it imitates, and a punycode host stays in its xn-- form.
        let cyrillicLookalike = WebExtensionRouter.httpsHost(
            fromOrigin: "https://аpple.com") // Cyrillic "а"
        XCTAssertNotEqual(cyrillicLookalike, "apple.com")
        XCTAssertEqual(WebExtensionRouter.httpsHost(fromOrigin: "https://xn--80ak6aa92e.com"),
                       "xn--80ak6aa92e.com")
        XCTAssertEqual(WebExtensionRouter.httpsHost(fromOrigin: "https://EXAMPLE.com"),
                       "example.com")
    }

    // MARK: - Value-leak sweep

    /// Serializes every metadata command's response and asserts a seeded
    /// secret never appears: `getFillPayload` stays the only value-returning
    /// command in the protocol.
    func testMetadataCommandsNeverCarryVaultValues() async throws {
        let secret = "sup3r-fuzz-secret"
        let item = WebExtensionTestSeed.login(title: "Fuzz Site",
                                              username: "fuzz-user",
                                              password: secret,
                                              website: "https://fuzz.example")
        try WebExtensionTestSeed.insert(item, into: store, key: key)

        let requests: [[String: Any]] = [
            ["cmd": "status", "v": 1],
            ["cmd": "saveGate", "v": 1, "origin": "https://fuzz.example"],
            ["cmd": "siteSettings", "v": 1, "origin": "https://fuzz.example"],
            ["cmd": "listItems", "v": 1, "origin": "https://fuzz.example"],
        ]
        for request in requests {
            let response = await WebExtensionRouter.route(request, context: liveContext())
            XCTAssertEqual(response["ok"] as? Bool, true, "cmd: \(request["cmd"] ?? "?")")
            let serialized = try JSONSerialization.data(withJSONObject: response)
            let text = String(decoding: serialized, as: UTF8.self)
            XCTAssertFalse(text.contains(secret), "cmd: \(request["cmd"] ?? "?")")
            let data = response["data"] as? [String: Any] ?? [:]
            XCTAssertNil(data["values"], "only getFillPayload may carry a values payload")
        }
    }
}
