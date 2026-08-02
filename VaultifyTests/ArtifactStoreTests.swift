import Foundation
import XCTest
@testable import Vaultify

/// The artifact lifecycle contract: staged import commits atomically into
/// record + ciphertext file, rollback and reconcile leave no orphans, a
/// record without bytes is an honest recoverable state (never a silent drop),
/// deletion cascades as tombstone + file removal, and legacy `AttachmentStore`
/// blobs adopt losslessly without destroying the originals.
@MainActor
final class ArtifactStoreTests: XCTestCase {

    private let testKey = [UInt8](repeating: 0x2a, count: 32)
    private let payload = Data("secret document bytes".utf8)
    private let ownerID = "owner-item-1"

    private func makeStack() -> (artifacts: ArtifactStore, store: VaultStore,
                                 session: VaultSession, root: URL) {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: testKey)
        let store = VaultStore(inMemory: true)
        let root = FileManager.default.temporaryDirectory
            .appending(path: "artifact-store-tests-\(UUID().uuidString)")
        let artifacts = ArtifactStore(session: session, store: store, directory: root)
        TestLifetimeRetainer.retain(store, session, artifacts)
        return (artifacts, store, session, root)
    }

    // MARK: Stage / commit / rollback

    func testStageCommitRoundTripsBytesAndManifest() throws {
        let (artifacts, store, _, root) = makeStack()

        let staged = try artifacts.stage(data: payload, filename: "doc.pdf", uti: "com.adobe.pdf")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.fileURL.path),
                      "staging must hold ciphertext on disk, not plaintext in memory")

        let record = try artifacts.commit(staged, ownerItemId: ownerID)
        XCTAssertEqual(record.ownerItemId, ownerID)
        XCTAssertEqual(record.relativePath, "\(staged.id).enc")
        XCTAssertTrue(artifacts.hasBytes(record))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.fileURL.path),
                       "commit consumes the staging file")
        XCTAssertNotNil(store.artifactRecord(id: staged.id))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appending(path: record.relativePath).path))

        XCTAssertEqual(try artifacts.loadPlaintext(record), payload)
        let manifest = try artifacts.manifest(for: record)
        XCTAssertEqual(manifest.filename, "doc.pdf")
        XCTAssertEqual(manifest.utiType, "com.adobe.pdf")
        XCTAssertEqual(manifest.plaintextByteCount, payload.count)
        XCTAssertEqual(manifest.plaintextSHA256, ArtifactCrypto.sha256(payload))
    }

    func testRollbackDeletesTheStagedCiphertext() throws {
        let (artifacts, store, _, _) = makeStack()
        let staged = try artifacts.stage(data: payload, filename: "a.txt", uti: "public.plain-text")

        artifacts.rollback(staged)

        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.fileURL.path))
        XCTAssertNil(store.artifactRecord(id: staged.id))
    }

    func testStageRequiresAnUnlockedVault() {
        let session = VaultSession(settings: SettingsStore())
        let store = VaultStore(inMemory: true)
        let root = FileManager.default.temporaryDirectory
            .appending(path: "artifact-store-tests-\(UUID().uuidString)")
        let artifacts = ArtifactStore(session: session, store: store, directory: root)
        TestLifetimeRetainer.retain(store, session, artifacts)

        XCTAssertThrowsError(try artifacts.stage(data: payload, filename: "a", uti: "public.data")) {
            XCTAssertEqual($0 as? ArtifactStore.Failure, .locked)
        }
    }

    // MARK: Missing bytes are an honest state

    func testMissingFileReadsAsMissingBytesNotAsCorruption() throws {
        let (artifacts, _, _, root) = makeStack()
        let staged = try artifacts.stage(data: payload, filename: "doc", uti: "public.data")
        let record = try artifacts.commit(staged, ownerItemId: ownerID)

        try FileManager.default.removeItem(at: root.appending(path: record.relativePath))

        XCTAssertFalse(artifacts.hasBytes(record))
        XCTAssertThrowsError(try artifacts.loadPlaintext(record)) {
            XCTAssertEqual($0 as? ArtifactStore.Failure, .missingBytes)
        }
        // The record survives — recoverable state, never a silent drop.
        XCTAssertNotNil(artifacts.record(id: record.id))
    }

    // MARK: Reconcile sweep

    func testReconcileSweepsOrphansButKeepsHonestMissingRecords() throws {
        let (artifacts, _, _, root) = makeStack()
        // A committed artifact whose bytes then vanish (honest missing state).
        let missing = try artifacts.commit(
            try artifacts.stage(data: payload, filename: "keep", uti: "public.data"),
            ownerItemId: ownerID)
        try FileManager.default.removeItem(at: root.appending(path: missing.relativePath))
        // A healthy committed artifact.
        let healthy = try artifacts.commit(
            try artifacts.stage(data: Data([9, 9]), filename: "ok", uti: "public.data"),
            ownerItemId: ownerID)
        // An abandoned staging file (editor killed mid-flow).
        let abandoned = try artifacts.stage(data: Data([1]), filename: "gone", uti: "public.data")
        // A ciphertext file no record describes.
        let garbage = root.appending(path: "\(UUID().uuidString).enc")
        try Data([0xde, 0xad]).write(to: garbage)

        artifacts.reconcile()

        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.fileURL.path),
                       "staging never survives reconcile")
        XCTAssertFalse(FileManager.default.fileExists(atPath: garbage.path),
                       "a file without a record is garbage")
        XCTAssertNotNil(artifacts.record(id: missing.id),
                        "a record without a file is honest missing state, not garbage")
        XCTAssertTrue(artifacts.hasBytes(healthy))
        XCTAssertEqual(try artifacts.loadPlaintext(healthy), Data([9, 9]))
    }

    // MARK: Cascade delete + erase

    func testDeleteArtifactsTombstonesAndRemovesBytes() throws {
        let (artifacts, store, _, root) = makeStack()
        let record = try artifacts.commit(
            try artifacts.stage(data: payload, filename: "doc", uti: "public.data"),
            ownerItemId: ownerID)

        artifacts.deleteArtifacts(ownerItemId: ownerID)

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appending(path: record.relativePath).path))
        XCTAssertTrue(artifacts.records(ownerItemId: ownerID).isEmpty)
        let tombstone = try XCTUnwrap(store.artifactRecord(id: record.id),
                                      "the tombstone must survive for sync reconciliation")
        XCTAssertNotNil(tombstone.deletedAt)
        XCTAssertTrue(tombstone.dirty)
    }

    func testEraseAllRemovesRecordsAndFiles() throws {
        let (artifacts, store, _, root) = makeStack()
        let record = try artifacts.commit(
            try artifacts.stage(data: payload, filename: "doc", uti: "public.data"),
            ownerItemId: ownerID)

        artifacts.eraseAll()

        XCTAssertNil(store.artifactRecord(id: record.id))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appending(path: record.relativePath).path))
    }

    // MARK: Plaintext temp export

    func testExportPlaintextWritesNamedFileAndCleanupSweepsIt() throws {
        let (artifacts, _, _, _) = makeStack()
        let record = try artifacts.commit(
            try artifacts.stage(data: payload, filename: "statement.pdf", uti: "com.adobe.pdf"),
            ownerItemId: ownerID)

        let url = try artifacts.exportPlaintext(record)
        XCTAssertEqual(url.lastPathComponent, "statement.pdf")
        XCTAssertEqual(try Data(contentsOf: url), payload)

        artifacts.cleanupTempExports()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: Legacy adoption

    func testLegacyAttachmentAdoptsLosslesslyAndIdempotently() throws {
        let (artifacts, _, session, _) = makeStack()
        let legacyDir = FileManager.default.temporaryDirectory
            .appending(path: "legacy-attachments-\(UUID().uuidString)")
        let legacy = AttachmentStore(session: session, directory: legacyDir)
        let meta = try legacy.save(payload, name: "scan.png", ext: "png")

        let adopted = try XCTUnwrap(artifacts.adoptLegacyAttachment(meta, ownerItemId: ownerID,
                                                                    from: legacy))
        XCTAssertEqual(adopted.id, meta.id, "the artifact keeps the legacy id")
        XCTAssertEqual(try artifacts.loadPlaintext(adopted), payload)
        XCTAssertEqual(try artifacts.manifest(for: adopted).filename, "scan.png")
        // Legacy bytes survive adoption — older builds still read them.
        XCTAssertEqual(try legacy.load(meta), payload)

        let again = try XCTUnwrap(artifacts.adoptLegacyAttachment(meta, ownerItemId: ownerID,
                                                                  from: legacy))
        XCTAssertEqual(again.id, adopted.id, "re-adoption returns the same artifact")
    }

    func testLegacyAdoptionReturnsNilWhenBytesAreAbsent() throws {
        let (artifacts, _, session, _) = makeStack()
        let legacyDir = FileManager.default.temporaryDirectory
            .appending(path: "legacy-attachments-\(UUID().uuidString)")
        let legacy = AttachmentStore(session: session, directory: legacyDir)
        let meta = AttachmentMeta(id: UUID().uuidString, name: "ghost.pdf", ext: "pdf", size: 12)

        XCTAssertNil(try artifacts.adoptLegacyAttachment(meta, ownerItemId: ownerID, from: legacy),
                     "absent legacy bytes adopt as nil — the honest missing state")
    }

    // MARK: Backup restore path

    func testRestoreAllInsertsValidatedPayloads() throws {
        let (artifacts, store, _, _) = makeStack()
        let id = UUID().uuidString
        try artifacts.restoreAll([VaultBackup.ArtifactPayload(
            id: id, ownerItemId: ownerID, filename: "doc.txt",
            utiType: "public.plain-text", data: payload)])

        let record = try XCTUnwrap(store.artifactRecord(id: id))
        XCTAssertEqual(try artifacts.loadPlaintext(record), payload)
        XCTAssertEqual(try artifacts.manifest(for: record).filename, "doc.txt")
    }
}
