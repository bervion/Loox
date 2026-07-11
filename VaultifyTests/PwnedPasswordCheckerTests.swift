import XCTest
import CryptoKit
@testable import Vaultify

/// HIBP checker orchestration: prefix grouping (request count), cache hits,
/// suffix matching, and failure propagation. Network is a URLProtocol mock.
final class PwnedPasswordCheckerTests: XCTestCase {

    /// Serves canned range responses and counts requests.
    final class MockHIBPProtocol: URLProtocol {
        nonisolated(unsafe) static var responses: [String: String] = [:]  // prefix → body
        nonisolated(unsafe) static var requestedPrefixes: [String] = []
        nonisolated(unsafe) static var failEverything = false
        static let lock = NSLock()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            let prefix = request.url!.lastPathComponent
            Self.requestedPrefixes.append(prefix)
            let body = Self.responses[prefix] ?? ""
            let fail = Self.failEverything
            Self.lock.unlock()

            if fail {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        static func reset() {
            lock.lock()
            responses = [:]; requestedPrefixes = []; failEverything = false
            lock.unlock()
        }
    }

    private var session: URLSession!
    private var cache: AuditLocalCache!

    override func setUp() {
        super.setUp()
        MockHIBPProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockHIBPProtocol.self]
        session = URLSession(configuration: config)
        cache = AuditLocalCache(secret: Array(repeating: 3, count: 64),
                                fileURL: FileManager.default.temporaryDirectory
                                    .appending(path: "pwned-cache-test-\(UUID().uuidString).bin"))
    }

    private func checker() -> PwnedPasswordChecker {
        PwnedPasswordChecker(session: session, cache: cache)
    }

    /// Registers `password` as pwned `count` times in the mock.
    private func registerPwned(_ password: String, count: Int) {
        let hex = PwnedPasswordChecker.sha1Hex(password)
        let prefix = String(hex.prefix(5)), suffix = String(hex.dropFirst(5))
        MockHIBPProtocol.lock.lock()
        MockHIBPProtocol.responses[prefix, default: ""] += "\(suffix):\(count)\n"
        MockHIBPProtocol.lock.unlock()
    }

    func testOneRequestPerUniquePrefixAndCorrectMatch() async throws {
        registerPwned("password", count: 12345)
        let counts = try await checker().counts(for: ["password", "password",
                                                      "unique-zebra-9$k"])
        XCTAssertEqual(counts["password"], 12345)
        XCTAssertEqual(counts["unique-zebra-9$k"], 0)
        // 2 unique passwords → at most 2 range requests (dedupe kills the 3rd).
        XCTAssertLessThanOrEqual(MockHIBPProtocol.requestedPrefixes.count, 2)
    }

    func testSecondRunServedEntirelyFromCache() async throws {
        registerPwned("password", count: 99)
        _ = try await checker().counts(for: ["password", "fresh-pw-1!x"])
        let firstRun = MockHIBPProtocol.requestedPrefixes.count
        _ = try await checker().counts(for: ["password", "fresh-pw-1!x"])
        XCTAssertEqual(MockHIBPProtocol.requestedPrefixes.count, firstRun,
                       "second run must not hit the network")
    }

    func testStaleCacheEntriesAreRefetched() async throws {
        await cache.store(counts: ["old-pw": 5],
                          now: Date(timeIntervalSinceNow: -AuditLocalCache.ttl - 60))
        registerPwned("old-pw", count: 7)
        let counts = try await checker().counts(for: ["old-pw"])
        XCTAssertEqual(counts["old-pw"], 7, "stale entry must be refreshed")
        XCTAssertFalse(MockHIBPProtocol.requestedPrefixes.isEmpty)
    }

    func testTotalFailureThrowsSoCoordinatorFlagsPartial() async {
        MockHIBPProtocol.lock.lock()
        MockHIBPProtocol.failEverything = true
        MockHIBPProtocol.lock.unlock()
        do {
            _ = try await checker().counts(for: ["whatever-pw"])
            XCTFail("offline lookup must throw, not silently return 0")
        } catch {}
        // And nothing bogus was cached.
        let cached = await cache.count(for: "whatever-pw")
        XCTAssertNil(cached)
    }

    func testCacheRoundtripsThroughSealedFile() async {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "pwned-cache-roundtrip-\(UUID().uuidString).bin")
        let secret = Array<UInt8>(repeating: 5, count: 64)
        let first = AuditLocalCache(secret: secret, fileURL: url)
        await first.store(counts: ["pw-x": 42])
        let second = AuditLocalCache(secret: secret, fileURL: url)
        let count = await second.count(for: "pw-x")
        XCTAssertEqual(count, 42)
        // File on disk is ciphertext, not JSON.
        let raw = try? Data(contentsOf: url)
        XCTAssertNotNil(raw)
        XCTAssertNil(try? JSONSerialization.jsonObject(with: raw!))
    }
}
