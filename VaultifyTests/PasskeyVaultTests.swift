import SwiftData
import XCTest
@testable import Vaultify

@MainActor
final class PasskeyVaultTests: XCTestCase {
    private let key = [UInt8](repeating: 0x2A, count: 32)

    func testSaveReadRoundtripReturnsMetadataOnlyAndSecretOnDemand() throws {
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let secret = makeSecret(relyingParty: "example.com", userName: "me")

        let result = try vault.save(secret, key: key)
        let info = try XCTUnwrap(vault.all(key: key).first)
        let reread = try XCTUnwrap(vault.secret(credentialID: secret.credentialID, key: key))

        XCTAssertTrue(result.replaced.isEmpty)
        XCTAssertEqual(info.relyingParty, secret.relyingParty)
        XCTAssertEqual(info.userName, secret.userName)
        XCTAssertEqual(info.credentialID, secret.credentialID)
        XCTAssertEqual(reread.privateKeyRaw, secret.privateKeyRaw)
        XCTAssertEqual(reread.flags, WebAuthn.newCredentialFlags)
    }

    func testReplaceOnDuplicateReturnsOldSecretAndKeepsOtherAccounts() throws {
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let old = makeSecret(relyingParty: "example.com", userName: "old", userHandle: Data([1]))
        let replacement = makeSecret(relyingParty: "example.com", userName: "new", userHandle: Data([1]))
        let other = makeSecret(relyingParty: "example.com", userName: "other", userHandle: Data([2]))

        _ = try vault.save(old, key: key)
        _ = try vault.save(other, key: key)
        let result = try vault.save(replacement, key: key)
        let all = vault.all(key: key)

        XCTAssertEqual(result.replaced.map(\.credentialID), [old.credentialID])
        XCTAssertEqual(all.map(\.credentialID).sortedLexicographically(),
                       [replacement.credentialID, other.credentialID].sortedLexicographically())
        XCTAssertNil(vault.secret(credentialID: old.credentialID, key: key))
    }

    func testFailedSaveLeavesExistingCredential() throws {
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let old = makeSecret(relyingParty: "example.com", userName: "old", userHandle: Data([1]))
        let replacement = makeSecret(relyingParty: "example.com", userName: "new", userHandle: Data([1]))

        _ = try vault.save(old, key: key)
        XCTAssertThrowsError(try vault.save(replacement, key: [1, 2, 3]))

        XCTAssertNotNil(vault.secret(credentialID: old.credentialID, key: key))
        XCTAssertNil(vault.secret(credentialID: replacement.credentialID, key: key))
    }

    func testDeleteTouchLastUsedAndOrdering() throws {
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let first = makeSecret(relyingParty: "example.com", userName: "first",
                               userHandle: Data([1]), createdAt: Date(timeIntervalSince1970: 1))
        let second = makeSecret(relyingParty: "example.com", userName: "second",
                                userHandle: Data([2]), createdAt: Date(timeIntervalSince1970: 2))

        _ = try vault.save(first, key: key)
        _ = try vault.save(second, key: key)
        vault.touchLastUsed(credentialID: first.credentialID)

        XCTAssertEqual(vault.matching(relyingParty: "example.com", allowedCredentialIDs: [], key: key).first?.credentialID,
                       first.credentialID)
        try vault.delete(credentialID: first.credentialID)
        XCTAssertNil(vault.secret(credentialID: first.credentialID, key: key))
        XCTAssertEqual(vault.all(key: key).map(\.credentialID), [second.credentialID])
    }

    func testEraseAllDeletesPasskeyRecords() throws {
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        _ = try PasskeyVault(store: store).save(makeSecret(relyingParty: "example.com", userName: "me"), key: key)

        try store.eraseAll()

        let records = try store.context.fetch(FetchDescriptor<PasskeyRecord>())
        XCTAssertTrue(records.isEmpty)
    }

    private func makeSecret(relyingParty: String,
                            userName: String,
                            userHandle: Data = Data([7]),
                            createdAt: Date = .now) -> PasskeySecret {
        let registration = WebAuthn.register(relyingParty: relyingParty)
        return PasskeySecret(relyingParty: relyingParty,
                             userName: userName,
                             userHandle: userHandle,
                             credentialID: registration.credentialID,
                             privateKeyRaw: registration.privateKeyRaw,
                             counter: 0,
                             createdAt: createdAt,
                             flags: registration.flags)
    }
}

private extension Array where Element == Data {
    func sortedLexicographically() -> [Data] {
        sorted { lhs, rhs in
            lhs.lexicographicallyPrecedes(rhs)
        }
    }
}
