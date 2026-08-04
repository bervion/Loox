import XCTest
import UIKit
@testable import Vaultify

/// Favicon lookups are the one place the app talks to a third party about the
/// user's own sites, so the limits on that traffic are pinned here: consent
/// gate, host completeness, one request per unique host, failure cooldown, and
/// a cache that is not a readable list of the user's accounts.
@MainActor
final class FaviconServiceTests: XCTestCase {

    /// Counts favicon requests and serves a canned PNG (or a failure).
    final class MockFaviconProtocol: URLProtocol {
        nonisolated(unsafe) private static var requestedHosts: [String] = []
        nonisolated(unsafe) private static var body: Data = Data()
        nonisolated(unsafe) private static var statusCode = 200
        nonisolated(unsafe) private static var offline = false
        private static let lock = NSLock()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            let host = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "domain" })?.value ?? ""
            Self.requestedHosts.append(host)
            let body = Self.body
            let status = Self.statusCode
            let offline = Self.offline
            Self.lock.unlock()

            if offline {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        static func reset(body: Data) {
            lock.lock()
            requestedHosts = []
            Self.body = body
            statusCode = 200
            offline = false
            lock.unlock()
        }

        static func failEverything() {
            lock.lock(); offline = true; lock.unlock()
        }

        static var hosts: [String] {
            lock.lock(); defer { lock.unlock() }
            return requestedHosts
        }
    }

    private var directory: URL!
    private var session: URLSession!

    /// A 4x4 PNG — real bytes, so `PlatformImage.fromData` succeeds the way it
    /// would with a live response.
    private static let iconData: Data = {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        return image.pngData()!
    }()

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appending(path: "favicon-tests-\(UUID().uuidString)")
        MockFaviconProtocol.reset(body: Self.iconData)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockFaviconProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeService() -> FaviconService {
        FaviconService(cacheDirectory: directory,
                       session: session,
                       cacheKey: Data(repeating: 0x5a, count: 32))
    }

    private func cacheFileNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    // MARK: - Consent gate

    /// `FaviconView` passes the user's `showWebsiteIcons` setting (and the
    /// subtree opt-out) in as `allowNetwork`, so this is the gate that decides
    /// whether anything reaches the network at all.
    func testNoRequestWhenNetworkIsNotAllowed() async {
        let service = makeService()

        let image = await service.fetchIcon(host: "example.com", allowNetwork: false)

        XCTAssertNil(image)
        XCTAssertTrue(MockFaviconProtocol.hosts.isEmpty)
        XCTAssertTrue(cacheFileNames().isEmpty)
    }

    func testCachedIconIsServedWithoutNetworkPermission() async {
        let warm = makeService()
        _ = await warm.fetchIcon(host: "example.com", allowNetwork: true)
        XCTAssertEqual(MockFaviconProtocol.hosts, ["example.com"])

        // A fresh instance reads the same directory, so this is the disk path.
        let service = makeService()
        let image = await service.fetchIcon(host: "example.com", allowNetwork: false)

        XCTAssertNotNil(image)
        XCTAssertEqual(MockFaviconProtocol.hosts, ["example.com"])
    }

    // MARK: - Host completeness

    func testPartialAndPrivateHostsAreNeverRequested() async {
        let service = makeService()
        let rejected = [
            "g", "go", "goo", "goog", "google", "google.",     // mid-typing
            "google.c", ".com", "google..com", "-google.com",
            "google-.com", "goo gle.com", "localhost", "nas.local",
            "vault.internal", "printer.lan", "192.168.1.4", "10.0.0.1",
            "site.onion",
        ]

        for host in rejected {
            let image = await service.fetchIcon(host: host, allowNetwork: true)
            XCTAssertNil(image, "\(host) should not resolve")
            XCTAssertFalse(FaviconService.isLookupEligible(host), "\(host) should be ineligible")
        }

        XCTAssertTrue(MockFaviconProtocol.hosts.isEmpty,
                      "half-typed and private hosts must never leave the device")
    }

    func testCompleteHostsAreEligible() {
        for host in ["google.com", "sub.domain.co.uk", "xn--80ak6aa92e.com", "a1.io"] {
            XCTAssertTrue(FaviconService.isLookupEligible(host), "\(host) should be eligible")
        }
    }

    func testHostParsingStripsSchemeAndWWW() {
        XCTAssertEqual(FaviconService.host(from: "https://www.GitHub.com/login"), "github.com")
        XCTAssertEqual(FaviconService.host(from: "example.com"), "example.com")
        XCTAssertNil(FaviconService.host(from: "   "))
    }

    // MARK: - Coalescing

    func testConcurrentRowsSharingAHostMakeOneRequestAndAllGetTheIcon() async {
        let service = makeService()

        async let first = service.fetchIcon(host: "example.com", allowNetwork: true)
        async let second = service.fetchIcon(host: "example.com", allowNetwork: true)
        async let third = service.fetchIcon(host: "example.com", allowNetwork: true)
        let images = await [first, second, third]

        XCTAssertEqual(MockFaviconProtocol.hosts, ["example.com"])
        XCTAssertEqual(images.compactMap { $0 }.count, 3,
                       "every row sharing a host must get the icon, not just the first")
    }

    func testEachUniqueHostIsRequestedOncePerRenderPass() async {
        let service = makeService()

        // Six rows resolving at once, three distinct hosts — the shape of a
        // vault list where several items share a site.
        async let a1 = service.fetchIcon(host: "a.com", allowNetwork: true)
        async let b1 = service.fetchIcon(host: "b.com", allowNetwork: true)
        async let a2 = service.fetchIcon(host: "a.com", allowNetwork: true)
        async let c1 = service.fetchIcon(host: "c.com", allowNetwork: true)
        async let b2 = service.fetchIcon(host: "b.com", allowNetwork: true)
        async let a3 = service.fetchIcon(host: "a.com", allowNetwork: true)
        let images = await [a1, b1, a2, c1, b2, a3]

        XCTAssertEqual(MockFaviconProtocol.hosts.sorted(), ["a.com", "b.com", "c.com"])
        XCTAssertEqual(images.compactMap { $0 }.count, 6)
    }

    // MARK: - Debounce

    func testCancellingDuringTheDebounceMakesNoRequest() async {
        let service = makeService()

        let task = Task { @MainActor in
            await service.fetchIcon(host: "example.com",
                                    allowNetwork: true,
                                    debounce: .milliseconds(600))
        }
        // Long enough for the fetch to reach its sleep, far short of the delay.
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let image = await task.value

        XCTAssertNil(image)
        XCTAssertTrue(MockFaviconProtocol.hosts.isEmpty,
                      "a keystroke during the debounce must cancel the lookup outright")
    }

    // MARK: - Negative cache

    func testFailedLookupIsNotRetriedDuringTheCooldown() async {
        MockFaviconProtocol.failEverything()
        let service = makeService()

        for _ in 0..<5 {
            let image = await service.fetchIcon(host: "example.com", allowNetwork: true)
            XCTAssertNil(image)
        }

        XCTAssertEqual(MockFaviconProtocol.hosts, ["example.com"],
                       "a failed host must not be re-requested on every render")
    }

    // MARK: - Cache naming and protection

    func testCacheFilenamesContainNoPlaintextHost() async {
        let service = makeService()
        _ = await service.fetchIcon(host: "example.com", allowNetwork: true)
        _ = await service.fetchIcon(host: "my-bank.co.uk", allowNetwork: true)

        let names = cacheFileNames()
        XCTAssertEqual(names.count, 2)
        for name in names {
            XCTAssertTrue(FaviconService.isHashedCacheName(name), "\(name) is not a hashed name")
            XCTAssertFalse(name.contains("example"))
            XCTAssertFalse(name.contains("bank"))
            XCTAssertFalse(name.contains("com"))
            XCTAssertFalse(name.contains("uk"))
        }
    }

    func testCachedFileIsWrittenWithCompleteProtection() async throws {
        let service = makeService()
        _ = await service.fetchIcon(host: "example.com", allowNetwork: true)

        let name = try XCTUnwrap(cacheFileNames().first)
        let attributes = try FileManager.default
            .attributesOfItem(atPath: directory.appending(path: name).path)
        // The simulator has no data protection and reports no protection class
        // at all; on a device the write must carry the complete class.
        let protection = attributes[.protectionKey] as? FileProtectionType
        try XCTSkipIf(protection == nil, "Data protection is not enforced on the simulator")
        XCTAssertEqual(protection, .complete)
    }

    func testLegacyPlaintextCacheFilesArePurgedOnInit() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("icon".utf8).write(to: directory.appending(path: "example.com.img"))
        try Data("icon".utf8).write(to: directory.appending(path: "my-bank.co.uk.img"))

        _ = makeService()

        XCTAssertTrue(cacheFileNames().isEmpty,
                      "the pre-hash naming was a plaintext account list and must not survive upgrade")
    }

    // MARK: - Erase

    func testClearCacheEmptiesTheDirectory() async {
        let service = makeService()
        _ = await service.fetchIcon(host: "example.com", allowNetwork: true)
        XCTAssertEqual(cacheFileNames().count, 1)

        service.clearCache()

        XCTAssertTrue(cacheFileNames().isEmpty)
        XCTAssertNil(service.cachedIcon(host: "example.com"))
    }

    func testClearCacheAlsoDropsTheInMemoryCopy() async {
        let service = makeService()
        _ = await service.fetchIcon(host: "example.com", allowNetwork: true)

        service.clearCache()

        // Nothing served without a new request: the memory copy went too.
        let image = await service.fetchIcon(host: "example.com", allowNetwork: false)
        XCTAssertNil(image)
        XCTAssertEqual(MockFaviconProtocol.hosts, ["example.com"])
    }
}
