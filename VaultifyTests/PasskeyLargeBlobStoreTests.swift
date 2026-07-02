import SwiftData
import XCTest
@testable import Vaultify

@MainActor
final class PasskeyLargeBlobStoreTests: XCTestCase {
    private let key = [UInt8](repeating: 0x2A, count: 32)

    func testWriteThenReadRoundtrips() throws {
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)

        let blob = Data("recovery-codes".utf8)
        XCTAssertTrue(vault.setLargeBlob(blob, credentialID: secret.credentialID, key: key))
        XCTAssertEqual(vault.largeBlob(credentialID: secret.credentialID, key: key), blob)
    }

    func testBlobIsSealed_notReadableWithWrongKey() throws {
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)
        _ = vault.setLargeBlob(Data("secret-blob".utf8), credentialID: secret.credentialID, key: key)

        XCTAssertNil(vault.largeBlob(credentialID: secret.credentialID, key: [UInt8](repeating: 0x11, count: 32)))
    }

    func testUnknownCredentialWriteFailsAndReadIsNil() throws {
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let missing = Data([9, 9, 9])

        XCTAssertFalse(vault.setLargeBlob(Data([1]), credentialID: missing, key: key))
        XCTAssertNil(vault.largeBlob(credentialID: missing, key: key))
    }

    func testOverwriteReplacesBlob() throws {
        let store = VaultStore(inMemory: true)
        TestLifetimeRetainer.retain(store)
        let vault = PasskeyVault(store: store)
        let secret = makeSecret()
        _ = try vault.save(secret, key: key)

        _ = vault.setLargeBlob(Data("first".utf8), credentialID: secret.credentialID, key: key)
        _ = vault.setLargeBlob(Data("second".utf8), credentialID: secret.credentialID, key: key)
        XCTAssertEqual(vault.largeBlob(credentialID: secret.credentialID, key: key), Data("second".utf8))
    }

    private func makeSecret() -> PasskeySecret {
        let registration = WebAuthn.register(relyingParty: "example.com")
        return PasskeySecret(relyingParty: "example.com", userName: "me", userHandle: Data([7]),
                             credentialID: registration.credentialID, privateKeyRaw: registration.privateKeyRaw,
                             counter: 0, createdAt: .now, flags: registration.flags)
    }
}
