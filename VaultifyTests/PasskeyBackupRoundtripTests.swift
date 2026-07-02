import XCTest
@testable import Vaultify

final class PasskeyBackupRoundtripTests: XCTestCase {
    private let passphrase = "correct horse battery staple"

    func testEncryptedBackupRoundTripsPasskeysAndPrivateKeyBytes() async throws {
        let item = VaultItem(category: .login, title: "GitHub",
                             fields: [DynamicField(label: "Website", kind: .url, value: "https://github.com")])
        let passkey = makeSecret(relyingParty: "github.com", userName: "octocat")

        let data = try await VaultBackup.exportEncrypted([item], passkeys: [passkey], passphrase: passphrase)
        let imported = try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase)

        XCTAssertEqual(imported.items.map(\.item.title), ["GitHub"])
        XCTAssertEqual(imported.passkeys.count, 1)
        XCTAssertEqual(imported.passkeys[0].credentialID, passkey.credentialID)
        XCTAssertEqual(imported.passkeys[0].privateKeyRaw, passkey.privateKeyRaw)
        XCTAssertEqual(imported.passkeys[0].flags, WebAuthn.newCredentialFlags)
    }

    func testLegacyEncryptedBackupWithoutPasskeysStillImports() async throws {
        let legacy = [VaultBackup.PortableItem(
            title: "Gmail",
            category: ItemCategory.login.rawValue,
            fields: [DynamicField(label: "Username", kind: .username, value: "me")])]
        let data = try await legacyBackup(items: legacy)

        let imported = try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase)

        XCTAssertEqual(imported.items.count, 1)
        XCTAssertEqual(imported.items[0].item.title, "Gmail")
        XCTAssertTrue(imported.passkeys.isEmpty)
    }

    func testEncryptedBackupRejectsInvalidPasskeyPayload() async throws {
        var invalid = makeSecret(relyingParty: "example.com", userName: "me")
        invalid.privateKeyRaw = Data([0x01, 0x02])
        let payload = TestPortableVaultPayload(items: [], passkeys: [invalid])
        let data = try await encryptedPayload(payload)

        await XCTAssertThrowsErrorAsync(
            try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase))
    }

    func testCSVExportNeverContainsPasskeyMaterial() {
        let passkey = makeSecret(relyingParty: "example.com", userName: "me")
        let csv = VaultBackup.makeCSV([])

        XCTAssertFalse(csv.contains(passkey.credentialID.base64EncodedString()))
        XCTAssertFalse(csv.contains(passkey.privateKeyRaw.base64EncodedString()))
        XCTAssertFalse(csv.localizedCaseInsensitiveContains("passkey"))
    }

    private struct TestPortableVaultPayload: Codable {
        var items: [VaultBackup.PortableItem]
        var passkeys: [PasskeySecret]?
    }

    private func legacyBackup(items: [VaultBackup.PortableItem]) async throws -> Data {
        try await encryptedPayload(items)
    }

    private func encryptedPayload(_ payload: some Encodable) async throws -> Data {
        let salt = KeyHierarchy.newSalt()
        let kdf = KdfParams.standard
        var kek = try await Task.detached {
            try KeyHierarchy.deriveKEK(passphrase: self.passphrase, salt: salt, params: kdf)
        }.value
        defer { secureZero(&kek) }
        let sealed = try AESGCM.seal(JSONEncoder().encode(payload), key: kek)
        return try JSONEncoder().encode(VaultBackup.EncryptedBackup(version: 1, salt: Data(salt),
                                                                    kdf: kdf, sealed: sealed))
    }

    private func makeSecret(relyingParty: String, userName: String) -> PasskeySecret {
        let registration = WebAuthn.register(relyingParty: relyingParty)
        return PasskeySecret(relyingParty: relyingParty,
                             userName: userName,
                             userHandle: Data([1, 2, 3]),
                             credentialID: registration.credentialID,
                             privateKeyRaw: registration.privateKeyRaw,
                             counter: 0,
                             createdAt: Date(timeIntervalSince1970: 1),
                             flags: registration.flags)
    }
}

private func XCTAssertThrowsErrorAsync<T>(_ expression: @autoclosure () async throws -> T,
                                          file: StaticString = #filePath,
                                          line: UInt = #line) async {
    do {
        _ = try await expression()
        XCTFail("Expected async throw", file: file, line: line)
    } catch {
    }
}
