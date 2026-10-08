import CryptoKit
import Foundation
import XCTest
@testable import Vaultify

/// Exercises the real transport and verification path with isolated HTTP cache
/// and generated signing keys. No production keys or network requests are used.
@MainActor
final class DomainRegistryRefreshTests: XCTestCase {
    nonisolated final class RegistryURLProtocol: URLProtocol, @unchecked Sendable {
        private nonisolated(unsafe) static var body = Data()
        private nonisolated(unsafe) static var statusCode = 200
        private nonisolated(unsafe) static var failure: URLError.Code?
        private nonisolated(unsafe) static var requests: [URLRequest] = []
        private static let lock = NSLock()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let state = Self.lock.withLock {
                Self.requests.append(request)
                return (Self.body, Self.statusCode, Self.failure)
            }
            if let error = state.2 {
                client?.urlProtocol(self, didFailWithError: URLError(error))
                return
            }
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: state.1, httpVersion: nil,
                                                 headerFields: ["Cache-Control": "public, max-age=3600"]) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: state.0)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        static func configure(body: Data = Data(), statusCode: Int = 200,
                              failure: URLError.Code? = nil) {
            lock.withLock {
                Self.body = body
                Self.statusCode = statusCode
                Self.failure = failure
                requests = []
            }
        }

        static var receivedRequests: [URLRequest] { lock.withLock { requests } }
    }

    private let registryURL = URL(string: "https://registry-refresh.example.invalid/v1/domain-registry")!

    private func withClient(
        _ operation: (DomainRegistryClient, P256.Signing.PrivateKey, URLCache) async throws -> Void
    ) async throws {
        let key = P256.Signing.PrivateKey()
        let suiteName = "domain-registry-refresh-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let cache = URLCache(memoryCapacity: 128 * 1024, diskCapacity: 0, diskPath: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = cache
        configuration.protocolClasses = [RegistryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = DomainRegistryClient(
            trustedKeys: ["refresh-test-key": key.publicKey.x963Representation],
            defaults: defaults, registryURL: registryURL, environment: "production", session: session)
        RegistryURLProtocol.configure()
        AuxiliaryDomainRegistry.applyRemote([])
        defer {
            session.invalidateAndCancel()
            cache.removeAllCachedResponses()
            defaults.removePersistentDomain(forName: suiteName)
            AuxiliaryDomainRegistry.applyRemote([])
            RegistryURLProtocol.configure()
        }
        try await operation(client, key, cache)
    }

    private func signedRegistry(
        version: UInt64, lifecycle: String, key: P256.Signing.PrivateKey,
        environment: String = "production", expiresAt: Int64 = .max,
        tamper: Bool = false
    ) throws -> Data {
        var json: [String: Any] = [
            "schema_version": 1, "registry_version": version, "key_id": "refresh-test-key",
            "env": environment, "issued_at": 0, "expires_at": expiresAt,
            "domains": [
                [
                    "id": "relay-main", "display_name": "relay.looxpassword.com",
                    "email_address_domain": "relay.looxpassword.com", "capabilities": ["email"],
                    "lifecycle": "active", "is_primary_email_choice": true,
                    "is_primary_short_link_choice": false,
                ],
                [
                    "id": "email-pw", "display_name": "loox.pw",
                    "email_address_domain": "loox.pw", "capabilities": ["email"],
                    "lifecycle": lifecycle, "is_primary_email_choice": false,
                    "is_primary_short_link_choice": false,
                ],
            ],
        ]
        let unsigned = try JSONSerialization.data(withJSONObject: json)
        let document = try JSONDecoder().decode(DomainRegistryDocument.self, from: unsigned)
        json["signature"] = try key.signature(for: document.transcript).rawRepresentation.base64EncodedString()
        if tamper {
            var domains = try XCTUnwrap(json["domains"] as? [[String: Any]])
            domains[1]["email_address_domain"] = "tampered.example.invalid"
            json["domains"] = domains
        }
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func seedTrustedActiveRegistry(_ client: DomainRegistryClient,
                                           key: P256.Signing.PrivateKey) throws {
        XCTAssertTrue(client.accept(documentData: try signedRegistry(version: 15, lifecycle: "active", key: key)))
    }

    private func assertTrustedStateRetained(_ client: DomainRegistryClient) {
        XCTAssertEqual(client.highestAcceptedVersion, 15)
        XCTAssertEqual(client.appliedRevision, 1)
        XCTAssertTrue(client.hasVerifiedCache)
        XCTAssertEqual(AuxiliaryDomainRegistry.descriptor(id: "email-pw")?.lifecycle, .active)
        XCTAssertEqual(AuxiliaryDomainRegistry.emailDomain(forDomainID: "relay-main"), "relay.looxpassword.com")
    }

    func testRefreshBypassesHTTPCacheToApplyNewSignedDomainLifecycle() async throws {
        try await withClient { client, key, cache in
            let previous = try signedRegistry(version: 14, lifecycle: "createDisabled", key: key)
            XCTAssertTrue(client.accept(documentData: previous))
            XCTAssertFalse(AuxiliaryDomainRegistry.creatableEmailDomains.contains { $0.id == "email-pw" })
            let cachedResponse = try XCTUnwrap(HTTPURLResponse(
                url: registryURL, statusCode: 200, httpVersion: nil,
                headerFields: ["Cache-Control": "public, max-age=3600",
                               "Content-Type": "application/json"]))
            let cacheRequest = URLRequest(url: registryURL)
            cache.storeCachedResponse(CachedURLResponse(response: cachedResponse, data: previous), for: cacheRequest)
            XCTAssertEqual(cache.cachedResponse(for: cacheRequest)?.data, previous)

            RegistryURLProtocol.configure(body: try signedRegistry(version: 15, lifecycle: "active", key: key))
            let refreshed = await client.refresh()
            XCTAssertTrue(refreshed)
            let requests = RegistryURLProtocol.receivedRequests
            XCTAssertEqual(requests.count, 1)
            let request = try XCTUnwrap(requests.first)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-cache")
            XCTAssertEqual(request.url, registryURL)
            XCTAssertEqual(client.highestAcceptedVersion, 15)
            XCTAssertEqual(client.appliedRevision, 2)
            XCTAssertTrue(AuxiliaryDomainRegistry.creatableEmailDomains.contains { $0.id == "email-pw" })
            XCTAssertEqual(AuxiliaryDomainRegistry.emailDomain(forDomainID: "email-pw"), "loox.pw")
            XCTAssertEqual(AuxiliaryDomainRegistry.emailDomain(forDomainID: "relay-main"), "relay.looxpassword.com")
        }
    }

    func testRefreshRejectsOlderRegistryAndRetainsTrustedState() async throws {
        try await withClient { client, key, _ in
            try seedTrustedActiveRegistry(client, key: key)
            RegistryURLProtocol.configure(body: try signedRegistry(version: 14, lifecycle: "createDisabled", key: key))
            let refreshed = await client.refresh()
            XCTAssertFalse(refreshed)
            assertTrustedStateRetained(client)
        }
    }

    func testRefreshRejectsTamperedRegistryAndRetainsTrustedState() async throws {
        try await withClient { client, key, _ in
            try seedTrustedActiveRegistry(client, key: key)
            RegistryURLProtocol.configure(body: try signedRegistry(version: 16, lifecycle: "active", key: key, tamper: true))
            let refreshed = await client.refresh()
            XCTAssertFalse(refreshed)
            assertTrustedStateRetained(client)
        }
    }

    func testRefreshRejectsWrongEnvironmentAndRetainsTrustedState() async throws {
        try await withClient { client, key, _ in
            try seedTrustedActiveRegistry(client, key: key)
            RegistryURLProtocol.configure(body: try signedRegistry(version: 16, lifecycle: "active", key: key,
                                                                   environment: "staging"))
            let refreshed = await client.refresh()
            XCTAssertFalse(refreshed)
            assertTrustedStateRetained(client)
        }
    }

    func testRefreshRejectsExpiredRegistryAndRetainsTrustedState() async throws {
        try await withClient { client, key, _ in
            try seedTrustedActiveRegistry(client, key: key)
            RegistryURLProtocol.configure(body: try signedRegistry(version: 16, lifecycle: "active", key: key,
                                                                   expiresAt: 1))
            let refreshed = await client.refresh()
            XCTAssertFalse(refreshed)
            assertTrustedStateRetained(client)
        }
    }

    func testNetworkFailureRetainsVerifiedRegistry() async throws {
        try await withClient { client, key, _ in
            try seedTrustedActiveRegistry(client, key: key)
            RegistryURLProtocol.configure(failure: .notConnectedToInternet)
            let refreshed = await client.refresh()
            XCTAssertFalse(refreshed)
            XCTAssertEqual(RegistryURLProtocol.receivedRequests.count, 1)
            assertTrustedStateRetained(client)
        }
    }

    func testHTTPFailureRetainsVerifiedRegistry() async throws {
        try await withClient { client, key, _ in
            try seedTrustedActiveRegistry(client, key: key)
            RegistryURLProtocol.configure(body: try signedRegistry(version: 16, lifecycle: "active", key: key),
                                          statusCode: 503)
            let refreshed = await client.refresh()
            XCTAssertFalse(refreshed)
            assertTrustedStateRetained(client)
        }
    }
}
