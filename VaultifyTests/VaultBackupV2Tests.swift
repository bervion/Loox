import Foundation
import XCTest
@testable import Vaultify

/// The v2 backup wire contract: item identity + metadata round trip losslessly,
/// artifacts restore byte-identical into a DIFFERENT vault key, v1 files still
/// import, and one corrupt artifact blob aborts the entire import before any
/// state could land (all-or-nothing).
@MainActor
final class VaultBackupV2Tests: XCTestCase {
    private let passphrase = "correct horse battery staple"

    // MARK: v2 round trip with artifacts

    func testV2RoundTripPreservesItemIdentityMetadataAndArtifactBytes() async throws {
        let itemID = UUID().uuidString
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let changedAt = Date(timeIntervalSince1970: 2_000)
        let updatedAt = Date(timeIntervalSince1970: 3_000)
        let item = VaultItem(id: itemID, category: .login, title: "Bank",
                             fields: [DynamicField(label: "Username", kind: .username, value: "me")],
                             favorite: true,
                             iconAsset: "dt_bank",
                             pinned: true,
                             rotateDays: 30,
                             passwordChangedAt: changedAt,
                             createdAt: createdAt,
                             updatedAt: updatedAt)
        let blob = Data((0 ..< 4096).map { UInt8($0 % 251) })
        let artifact = VaultBackup.ArtifactPayload(id: UUID().uuidString, ownerItemId: itemID,
                                                   filename: "statement.pdf",
                                                   utiType: "com.adobe.pdf", data: blob)

        let data = try await VaultBackup.exportEncrypted([item], artifacts: [artifact],
                                                         passphrase: passphrase)
        let imported = try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase)

        let restored = try XCTUnwrap(imported.items.first?.item)
        XCTAssertEqual(restored.id, itemID, "stable ids let artifacts re-attach to their owner")
        XCTAssertTrue(restored.favorite)
        XCTAssertTrue(restored.pinned)
        XCTAssertEqual(restored.iconAsset, "dt_bank")
        XCTAssertEqual(restored.rotateDays, 30)
        XCTAssertEqual(try XCTUnwrap(restored.passwordChangedAt).timeIntervalSince1970,
                       changedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.createdAt.timeIntervalSince1970,
                       createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(restored.updatedAt.timeIntervalSince1970,
                       updatedAt.timeIntervalSince1970, accuracy: 0.001)

        XCTAssertEqual(imported.artifacts.count, 1)
        XCTAssertEqual(imported.artifacts.first?.id, artifact.id)
        XCTAssertEqual(imported.artifacts.first?.ownerItemId, itemID)
        XCTAssertEqual(imported.artifacts.first?.filename, "statement.pdf")
        XCTAssertEqual(imported.artifacts.first?.data, blob, "restored bytes must be byte-identical")
    }

    func testV2ArtifactsRestoreIntoAVaultWithADifferentKey() async throws {
        let itemID = UUID().uuidString
        let blob = Data("the actual document".utf8)
        let artifact = VaultBackup.ArtifactPayload(id: UUID().uuidString, ownerItemId: itemID,
                                                   filename: "doc.txt",
                                                   utiType: "public.plain-text", data: blob)
        let data = try await VaultBackup.exportEncrypted(
            [VaultItem(id: itemID, category: .login, title: "Site")],
            artifacts: [artifact], passphrase: passphrase)

        let imported = try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase)

        // Destination vault: fresh store, DIFFERENT vault key — the backup's
        // artifacts must re-seal to it, not to the source hierarchy.
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: [UInt8](repeating: 0x77, count: 32))
        let store = VaultStore(inMemory: true)
        let root = FileManager.default.temporaryDirectory
            .appending(path: "backup-v2-tests-\(UUID().uuidString)")
        let artifacts = ArtifactStore(session: session, store: store, directory: root)
        TestLifetimeRetainer.retain(store, session, artifacts)

        try artifacts.restoreAll(imported.artifacts)

        let record = try XCTUnwrap(store.artifactRecord(id: artifact.id))
        XCTAssertEqual(record.ownerItemId, itemID)
        XCTAssertEqual(try artifacts.loadPlaintext(record), blob)
        XCTAssertEqual(try artifacts.manifest(for: record).filename, "doc.txt")
    }

    // MARK: v1 compatibility

    func testV1BackupStillImports() async throws {
        let legacy = [VaultBackup.PortableItem(
            title: "Gmail",
            category: ItemCategory.login.rawValue,
            fields: [DynamicField(label: "Username", kind: .username, value: "me")]),
                      VaultBackup.PortableItem(
            title: "Future thing",
            category: "category_from_a_newer_build",
            fields: [])]
        let data = try await v1Backup(payload: TestPayload(items: legacy, passkeys: nil,
                                                           artifacts: nil))

        let imported = try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase)

        XCTAssertEqual(imported.items.count, 2)
        XCTAssertEqual(imported.items[0].item.title, "Gmail")
        XCTAssertFalse(imported.items[0].item.id.isEmpty,
                       "a v1 item without an id gets a fresh one")
        XCTAssertTrue(imported.artifacts.isEmpty)
        // The unknown-category preservation contract survives the v2 change.
        XCTAssertEqual(imported.items[1].item.category, .custom)
        XCTAssertEqual(imported.items[1].item.unknownCategoryRaw, "category_from_a_newer_build")
    }

    // MARK: All-or-nothing artifact validation

    func testArtifactWithWrongHashAbortsTheWholeImport() async throws {
        let blob = Data("bytes".utf8)
        let data = try await v2Backup { contentKey in
            var artifact = try self.makeWireArtifact(blob: blob, contentKey: contentKey)
            artifact.plaintextSHA256 = Data(repeating: 0, count: 32)
            return TestPayload(items: [Self.plainItem()], passkeys: nil, artifacts: [artifact])
        }

        await assertImportThrowsArtifactCorrupt(data)
    }

    func testTruncatedArtifactBlobAbortsTheWholeImport() async throws {
        let blob = Data("bytes".utf8)
        let data = try await v2Backup { contentKey in
            var artifact = try self.makeWireArtifact(blob: blob, contentKey: contentKey)
            artifact.blob = artifact.blob.dropLast(4)
            return TestPayload(items: [Self.plainItem()], passkeys: nil, artifacts: [artifact])
        }

        await assertImportThrowsArtifactCorrupt(data)
    }

    func testArtifactWithWrongDeclaredLengthAbortsTheWholeImport() async throws {
        let blob = Data("bytes".utf8)
        let data = try await v2Backup { contentKey in
            var artifact = try self.makeWireArtifact(blob: blob, contentKey: contentKey)
            artifact.byteCount = blob.count + 1
            return TestPayload(items: [Self.plainItem()], passkeys: nil, artifacts: [artifact])
        }

        await assertImportThrowsArtifactCorrupt(data)
    }

    private func assertImportThrowsArtifactCorrupt(_ data: Data,
                                                   file: StaticString = #filePath,
                                                   line: UInt = #line) async {
        do {
            _ = try await VaultBackup.importEncryptedWithPasskeys(data, passphrase: passphrase)
            XCTFail("a corrupt artifact must abort the whole import", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? VaultBackup.BackupFailure, .artifactCorrupt,
                           file: file, line: line)
        }
    }

    // MARK: Wire construction helpers

    private struct TestPayload: Codable {
        var items: [VaultBackup.PortableItem]
        var passkeys: [PasskeySecret]?
        var artifacts: [VaultBackup.PortableArtifact]?
    }

    private static func plainItem() -> VaultBackup.PortableItem {
        VaultBackup.PortableItem(title: "Site", category: ItemCategory.login.rawValue, fields: [])
    }

    /// A correctly sealed wire artifact — tests then break exactly one thing.
    private func makeWireArtifact(blob: Data, contentKey: SecureBytes) throws -> VaultBackup.PortableArtifact {
        let id = "artifact-1"
        let owner = "item-1"
        var blobKey = ArtifactCrypto.newDEK()
        defer { secureZero(&blobKey) }
        return VaultBackup.PortableArtifact(
            id: id, ownerItemId: owner, filename: "f.bin", utiType: "public.data",
            byteCount: blob.count,
            plaintextSHA256: ArtifactCrypto.sha256(blob),
            wrappedKey: try ArtifactCrypto.wrapDEK(blobKey, under: contentKey,
                                                   artifactID: id, ownerItemID: owner),
            blob: try ArtifactCrypto.sealArtifact(plaintext: blob, dek: blobKey,
                                                  artifactID: id, ownerItemID: owner,
                                                  purpose: ArtifactCrypto.purposeBackup))
    }

    private func v1Backup(payload: some Encodable) async throws -> Data {
        let salt = KeyHierarchy.newSalt()
        let kdf = KdfParams.standard
        var kek = try await deriveKEK(salt: salt, kdf: kdf)
        defer { secureZero(&kek) }
        let sealed = try AESGCM.seal(JSONEncoder().encode(payload), key: kek)
        return try JSONEncoder().encode(VaultBackup.EncryptedBackup(
            version: 1, salt: Data(salt), kdf: kdf, sealed: sealed))
    }

    private func v2Backup(makePayload: (SecureBytes) throws -> TestPayload) async throws -> Data {
        let salt = KeyHierarchy.newSalt()
        let kdf = KdfParams.standard
        var kek = try await deriveKEK(salt: salt, kdf: kdf)
        defer { secureZero(&kek) }
        var contentKey = CryptoRandom.bytes(32)
        defer { secureZero(&contentKey) }
        let payload = try makePayload(SecureBytes(contentKey))
        let sealed = try AESGCM.seal(JSONEncoder().encode(payload), key: contentKey)
        let wrappedCK = try AESGCM.seal(Data(contentKey), key: kek)
        return try JSONEncoder().encode(VaultBackup.EncryptedBackup(
            version: 2, salt: Data(salt), kdf: kdf, sealed: sealed, wrappedCK: wrappedCK))
    }

    private func deriveKEK(salt: [UInt8], kdf: KdfParams) async throws -> [UInt8] {
        let phrase = passphrase
        return try await Task.detached {
            try KeyHierarchy.deriveKEK(passphrase: phrase, salt: salt, params: kdf)
        }.value
    }
}
