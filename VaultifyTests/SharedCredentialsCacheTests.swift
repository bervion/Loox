import XCTest
@testable import Vaultify

/// Round-trip + fail-closed invariants for the AutoFill shared-credentials cache
/// (VaultifyCore/Sharing/SharedCredentialsCache.swift).
final class SharedCredentialsCacheTests: XCTestCase {
    private let key = [UInt8](repeating: 0x3C, count: 32)

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: SharedConfig.containerURL,
                                                withIntermediateDirectories: true)
        SharedCredentialsCache.clear()
    }

    override func tearDownWithError() throws {
        SharedCredentialsCache.clear()
    }

    private func makeEntry(id: String = "shared::_owner1::apz-abc") -> SharedCredentialEntry {
        SharedCredentialEntry(itemID: id, title: "GitHub", websiteHost: "github.com",
                              username: "me@example.com", password: "hunter2",
                              zoneName: "apz-abc", ownerName: "_owner1", grantId: "grant-1",
                              askEachTimeTOTPFieldId: "f-totp")
    }

    func testRoundTripSealAndLoad() throws {
        let entries = [makeEntry()]
        try SharedCredentialsCache.save(entries: entries, vaultKey: key)
        XCTAssertEqual(SharedCredentialsCache.load(vaultKey: SecureBytes(key)), entries)
    }

    func testLoadWithWrongKeyFailsClosedToEmpty() throws {
        try SharedCredentialsCache.save(entries: [makeEntry()], vaultKey: key)
        let wrongKey = [UInt8](repeating: 0x00, count: 32)
        XCTAssertEqual(SharedCredentialsCache.load(vaultKey: SecureBytes(wrongKey)), [])
    }

    func testLoadWithNoFileYieldsEmpty() {
        XCTAssertEqual(SharedCredentialsCache.load(vaultKey: SecureBytes(key)), [])
    }

    func testEmptySaveOverwritesPreviousEntries() throws {
        try SharedCredentialsCache.save(entries: [makeEntry()], vaultKey: key)
        try SharedCredentialsCache.save(entries: [], vaultKey: key)
        XCTAssertEqual(SharedCredentialsCache.load(vaultKey: SecureBytes(key)), [])
    }

    func testClearRemovesFile() throws {
        try SharedCredentialsCache.save(entries: [makeEntry()], vaultKey: key)
        SharedCredentialsCache.clear()
        XCTAssertEqual(SharedCredentialsCache.load(vaultKey: SecureBytes(key)), [])
    }

    func testHostMatchingIsSubdomainTolerantAndEmptyRequestMatchesAny() {
        let entry = makeEntry()
        XCTAssertTrue(entry.matchesAutoFill(serviceIdentifiers: ["www.github.com"]))
        XCTAssertTrue(entry.matchesAutoFill(serviceIdentifiers: []))
        XCTAssertFalse(entry.matchesAutoFill(serviceIdentifiers: ["example.com"]))
    }

    func testHostMatchingFailsClosedWithoutHost() {
        var entry = makeEntry()
        entry.websiteHost = nil
        XCTAssertFalse(entry.matchesAutoFill(serviceIdentifiers: ["github.com"]))
    }
}
