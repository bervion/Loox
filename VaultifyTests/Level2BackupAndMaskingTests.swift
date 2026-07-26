import XCTest
@testable import Vaultify

/// The Extra Protection contract outside the item detail screen: sealed values
/// never surface (subtitles, search, CSV) and the encrypted backup carries the
/// wrapped L2SK so a restore can still open level2-sealed fields.
final class Level2BackupAndMaskingTests: XCTestCase {
    private let passphrase = "correct horse battery staple"

    private func sealedField(kind: FieldKind = .password, label: String = "Password") -> DynamicField {
        DynamicField(label: label, kind: kind,
                     value: "v2g:c2VhbGVkLXBheWxvYWQ=", protected: true, guard2: true)
    }

    func testEncryptedBackupRoundTripsLevel2Wrap() async throws {
        let item = VaultItem(category: .login, title: "Mail", fields: [sealedField()])
        let wrap = VaultBackup.Level2Wrap(wrappedL2SK: Data([9, 9, 9]),
                                          salt: Data([1, 2, 3, 4]),
                                          kdf: .standard)

        let data = try await VaultBackup.exportEncrypted([item], level2: wrap, passphrase: passphrase)
        let imported = try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase)

        XCTAssertEqual(imported.level2?.wrappedL2SK, wrap.wrappedL2SK)
        XCTAssertEqual(imported.level2?.salt, wrap.salt)
        // The sealed value itself must survive untouched — it is the data.
        XCTAssertEqual(imported.items.first?.item.fields.first?.guard2, true)
        XCTAssertEqual(imported.items.first?.item.fields.first?.value, sealedField().value)
    }

    func testBackupWithoutLevel2StaysCompatibleBothWays() async throws {
        let item = VaultItem(category: .login, title: "Plain", fields: [])
        let data = try await VaultBackup.exportEncrypted([item], passphrase: passphrase)

        let imported = try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase)

        XCTAssertNil(imported.level2)
        XCTAssertEqual(imported.items.count, 1)
    }

    func testCSVMasksSealedValuesInsteadOfExportingCiphertext() {
        let item = VaultItem(category: .login, title: "Bank", fields: [
            DynamicField(label: "Username", kind: .username, value: "me@example.com"),
            sealedField(),
        ])

        let csv = VaultBackup.makeCSV([item])

        XCTAssertTrue(csv.contains("[protected]"))
        XCTAssertTrue(csv.contains("me@example.com"))
        XCTAssertFalse(csv.contains("v2g:"))
    }

    func testSubtitleAndSearchNeverSurfaceSealedValues() {
        let item = VaultItem(category: .login, title: "Site", fields: [
            sealedField(kind: .username, label: "Username"),
            DynamicField(label: "Website", kind: .url, value: "https://example.com"),
        ])

        // The sealed username is skipped; the next usable field wins.
        XCTAssertEqual(item.subtitle, "https://example.com")
        XCTAssertFalse(item.searchText.contains("v2g:"))
    }

    func testUsableTOTPFieldExcludesSealedSeed() {
        let item = VaultItem(category: .login, title: "OTP", fields: [
            sealedField(kind: .totp, label: "One-time Code"),
        ])

        XCTAssertNil(item.totpField)
    }
}
