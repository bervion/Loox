import Foundation
import SwiftData
import UniformTypeIdentifiers

/// A staged (encrypted, not yet committed) artifact import. The ciphertext
/// already sits on disk in the staging directory sealed under the artifact's
/// DEK; the DEK lives only in this value until `commit` wraps it under the
/// Vault Key. Dropping the value without committing leaves an orphan staging
/// file that `reconcile()` sweeps at the next unlock.
struct StagedArtifact {
    let id: String
    let fileURL: URL
    let filename: String
    let utiType: String
    let plaintextByteCount: Int
    let plaintextSHA256: Data
    fileprivate let dek: SecureBytes
}

/// First-class encrypted artifact lifecycle: staged import → commit, honest
/// missing-bytes reads, cascade delete, recovery journal + reconcile sweep,
/// plaintext temp exports, and lazy adoption of legacy `AttachmentStore` blobs.
///
/// Files live under the App Group `Artifacts-v2/` root as `<id>.enc` (the id is
/// a random UUID, so names leak nothing). Records live in the SwiftData store
/// (`ArtifactRecord`). The two can legitimately disagree in exactly one
/// direction: a record whose file is absent is the honest "bytes not on this
/// device" state; a file without a record is garbage and gets deleted.
@MainActor final class ArtifactStore {
    enum Failure: Error, Equatable {
        case locked
        /// The record exists but its ciphertext file is not on this device.
        case missingBytes
        case stagingFileMissing
        /// The on-disk envelope does not match the record's ciphertext hash.
        case integrityMismatch
    }

    private let session: VaultSession
    private let store: VaultStore
    private let root: URL

    private var stagingDirectory: URL { root.appending(path: "staging") }
    private var journalURL: URL { root.appending(path: "journal.json") }
    /// All plaintext temp exports live under this one root so one sweep can
    /// remove every per-action directory regardless of which flow made it.
    private let tempExportRoot: URL

    init(session: VaultSession, store: VaultStore, directory: URL? = nil) {
        self.session = session
        self.store = store
        self.root = directory ?? SharedConfig.containerURL.appending(path: "Artifacts-v2")
        self.tempExportRoot = FileManager.default.temporaryDirectory
            .appending(path: "artifact-exports")
        try? FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
    }

    private func fileURL(for record: ArtifactRecord) -> URL {
        root.appending(path: record.relativePath)
    }

    // MARK: Staged import

    /// Encrypt `data` into the staging area under a fresh per-artifact DEK.
    /// No record is created and the Vault Key is untouched — cancelling the
    /// editor just calls `rollback` (or lets `reconcile()` sweep the file).
    func stage(data: Data, filename: String, uti: String) throws -> StagedArtifact {
        guard session.vaultKey != nil else { throw Failure.locked }
        let id = UUID().uuidString
        var dek = ArtifactCrypto.newDEK()
        defer { secureZero(&dek) }
        // Staged bytes are sealed to a staging owner placeholder: the real
        // owner may not exist yet (the item is still an unsaved draft), and
        // commit re-seals under the final owner AAD so nothing sealed for
        // staging is ever accepted as a committed artifact.
        let envelope = try ArtifactCrypto.sealArtifact(
            plaintext: data, dek: dek, artifactID: id,
            ownerItemID: ArtifactCrypto.stagingOwnerID, purpose: ArtifactCrypto.purposeFile)
        let url = stagingDirectory.appending(path: id)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try envelope.write(to: url, options: [.atomic, .completeFileProtection])
        appendJournal(op: "stage", artifactID: id, path: "staging/\(id)")
        return StagedArtifact(id: id, fileURL: url, filename: filename, utiType: uti,
                              plaintextByteCount: data.count,
                              plaintextSHA256: ArtifactCrypto.sha256(data),
                              dek: SecureBytes(dek))
    }

    /// Bind a staged artifact to its owner: re-seal under the final AAD, move
    /// the ciphertext into place, wrap the DEK under the Vault Key, and insert
    /// the `ArtifactRecord`. With `deferSave: true` the caller owns the
    /// surrounding `context.save()` (so the artifact lands in the SAME save as
    /// the item edit); otherwise this commits its own save.
    @discardableResult
    func commit(_ staged: StagedArtifact, ownerItemId: String,
                deferSave: Bool = false) throws -> ArtifactRecord {
        guard let vaultKey = session.vaultKey else { throw Failure.locked }
        guard FileManager.default.fileExists(atPath: staged.fileURL.path) else {
            throw Failure.stagingFileMissing
        }
        var dek = staged.dek.bytes
        defer { secureZero(&dek) }
        let stagedEnvelope = try Data(contentsOf: staged.fileURL)
        let plaintext = try ArtifactCrypto.openArtifact(
            envelope: stagedEnvelope, dek: dek, artifactID: staged.id,
            ownerItemID: ArtifactCrypto.stagingOwnerID, purpose: ArtifactCrypto.purposeFile)
        let envelope = try ArtifactCrypto.sealArtifact(
            plaintext: plaintext, dek: dek, artifactID: staged.id,
            ownerItemID: ownerItemId, purpose: ArtifactCrypto.purposeFile)
        let manifest = ArtifactManifest(filename: staged.filename, utiType: staged.utiType,
                                        plaintextByteCount: staged.plaintextByteCount,
                                        plaintextSHA256: staged.plaintextSHA256)
        let record = ArtifactRecord(
            id: staged.id,
            ownerItemId: ownerItemId,
            wrappedDEK: try ArtifactCrypto.wrapDEK(dek, under: vaultKey,
                                                   artifactID: staged.id, ownerItemID: ownerItemId),
            sealedManifest: try ArtifactCrypto.sealManifest(manifest, dek: dek,
                                                            artifactID: staged.id, ownerItemID: ownerItemId),
            relativePath: "\(staged.id).enc",
            byteCount: envelope.count,
            ciphertextHash: ArtifactCrypto.sha256(envelope))
        let finalURL = root.appending(path: record.relativePath)
        try envelope.write(to: finalURL, options: [.atomic, .completeFileProtection])
        store.context.insert(record)
        if !deferSave { try store.context.save() }
        try? FileManager.default.removeItem(at: staged.fileURL)
        appendJournal(op: "commit", artifactID: staged.id, path: record.relativePath)
        return record
    }

    /// Discard a staged artifact (editor cancelled).
    func rollback(_ staged: StagedArtifact) {
        try? FileManager.default.removeItem(at: staged.fileURL)
        appendJournal(op: "rollback", artifactID: staged.id, path: "staging/\(staged.id)")
    }

    // MARK: Reads

    /// Live artifacts owned by an item.
    func records(ownerItemId: String) -> [ArtifactRecord] {
        store.artifactRecords(ownerItemId: ownerItemId)
    }

    func record(id: String) -> ArtifactRecord? {
        store.artifactRecord(id: id)
    }

    /// Whether the ciphertext bytes are present on this device. False is the
    /// honest "missing bytes" state, never an error.
    func hasBytes(_ record: ArtifactRecord) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: record).path)
    }

    /// Decrypt an artifact into memory. Verifies the envelope against the
    /// record's ciphertext hash before opening.
    func loadPlaintext(_ record: ArtifactRecord) throws -> Data {
        guard let vaultKey = session.vaultKey else { throw Failure.locked }
        let url = fileURL(for: record)
        // Size gate from file metadata BEFORE the bytes are read into memory.
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        else { throw Failure.missingBytes }
        guard size <= ArtifactCrypto.maxEnvelopeBytes else {
            throw ArtifactCrypto.Failure.oversize(byteCount: size)
        }
        let envelope = try Data(contentsOf: url)
        guard ArtifactCrypto.sha256(envelope) == record.ciphertextHash else {
            throw Failure.integrityMismatch
        }
        var dek = try ArtifactCrypto.unwrapDEK(record.wrappedDEK, under: vaultKey,
                                               artifactID: record.id, ownerItemID: record.ownerItemId)
        defer { secureZero(&dek) }
        return try ArtifactCrypto.openArtifact(
            envelope: envelope, dek: dek, artifactID: record.id,
            ownerItemID: record.ownerItemId, purpose: ArtifactCrypto.purposeFile)
    }

    /// Open the sealed manifest (filename, UTI, plaintext size + hash).
    func manifest(for record: ArtifactRecord) throws -> ArtifactManifest {
        guard let vaultKey = session.vaultKey else { throw Failure.locked }
        var dek = try ArtifactCrypto.unwrapDEK(record.wrappedDEK, under: vaultKey,
                                               artifactID: record.id, ownerItemID: record.ownerItemId)
        defer { secureZero(&dek) }
        return try ArtifactCrypto.openManifest(record.sealedManifest, dek: dek,
                                               artifactID: record.id, ownerItemID: record.ownerItemId)
    }

    // MARK: Plaintext temp export (QuickLook / share)

    /// Decrypt to a protected file in a fresh per-action random directory so
    /// concurrent exports never collide and a single sweep can drop them all.
    /// Callers hand the URL to QuickLook/ShareLink; `cleanupTempExports()`
    /// removes every export directory (wire it at dismiss/lock/launch).
    func exportPlaintext(_ record: ArtifactRecord) throws -> URL {
        let data = try loadPlaintext(record)
        let manifest = try manifest(for: record)
        let directory = tempExportRoot.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = manifest.filename.isEmpty ? record.id : manifest.filename
        let url = directory.appending(path: name)
        try data.write(to: url, options: [.completeFileProtection])
        return url
    }

    /// Remove every plaintext temp export directory ever produced by
    /// `exportPlaintext` (all flows share one root).
    func cleanupTempExports() {
        try? FileManager.default.removeItem(at: tempExportRoot)
    }

    // MARK: Deletion

    /// Cascade delete for an item: tombstone every owned artifact (sync needs
    /// the record to propagate the deletion) and remove the local ciphertext.
    func deleteArtifacts(ownerItemId: String) {
        let owned = store.artifactRecords(ownerItemId: ownerItemId)
        guard !owned.isEmpty else { return }
        for record in owned { tombstone(record) }
        try? store.context.save()
    }

    /// Tombstone one artifact and remove its ciphertext file.
    func delete(_ record: ArtifactRecord) {
        tombstone(record)
        try? store.context.save()
    }

    private func tombstone(_ record: ArtifactRecord) {
        let url = fileURL(for: record)
        record.deletedAt = .now
        record.updatedAt = .now
        record.dirty = true
        try? FileManager.default.removeItem(at: url)
        appendJournal(op: "delete", artifactID: record.id, path: record.relativePath)
    }

    /// Permanently drop everything: records, ciphertext files, staging,
    /// journal, and plaintext temp exports (used by "Erase Vault").
    func eraseAll() {
        try? store.context.delete(model: ArtifactRecord.self)
        try? store.context.save()
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        cleanupTempExports()
    }

    // MARK: Reconcile (unlock-time recovery sweep)

    /// Converge disk and store after crashes or interrupted flows:
    /// - every staging file is an orphan by definition (a commit removes its
    ///   staging source synchronously) → deleted;
    /// - a ciphertext file with no live record is garbage → deleted;
    /// - a record with no file is LEFT ALONE — that is the honest
    ///   "missing bytes" state (`hasBytes` false, `loadPlaintext` throws);
    /// - plaintext temp exports are swept (janitor);
    /// - the journal restarts empty once the sweep has converged.
    func reconcile() {
        let fm = FileManager.default
        if let staged = try? fm.contentsOfDirectory(at: stagingDirectory,
                                                    includingPropertiesForKeys: nil) {
            for url in staged { try? fm.removeItem(at: url) }
        }
        let all = store.allArtifactRecords()
        let livePaths = Set(all.filter { $0.deletedAt == nil }.map(\.relativePath))
        if let files = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for url in files where url.pathExtension == "enc" {
                if !livePaths.contains(url.lastPathComponent) {
                    try? fm.removeItem(at: url)
                }
            }
        }
        cleanupTempExports()
        try? fm.removeItem(at: journalURL)
    }

    // MARK: Legacy adoption

    /// Adopt a legacy `AttachmentStore` blob into a first-class artifact,
    /// re-sealed under its own DEK. Returns the existing record when the id
    /// was already adopted (idempotent), or nil when the legacy bytes are
    /// absent/undecryptable — the honest missing state, never a throw for it.
    /// The legacy file is deliberately NOT deleted: older builds sharing the
    /// container must keep reading it until the migration window closes.
    func adoptLegacyAttachment(_ meta: AttachmentMeta, ownerItemId: String,
                               from legacy: AttachmentStore) throws -> ArtifactRecord? {
        guard session.vaultKey != nil else { throw Failure.locked }
        if let existing = store.artifactRecord(id: meta.id), existing.deletedAt == nil {
            return existing
        }
        guard let data = try? legacy.load(meta) else { return nil }
        let uti = UTType(filenameExtension: meta.ext)?.identifier ?? UTType.data.identifier
        let record = try insertArtifact(id: meta.id, ownerItemId: ownerItemId,
                                        filename: meta.name, utiType: uti, data: data)
        try store.context.save()
        appendJournal(op: "adopt", artifactID: meta.id, path: record.relativePath)
        return record
    }

    // MARK: Backup restore

    /// Insert already-validated backup artifacts, re-sealed under THIS vault's
    /// key hierarchy. All-or-nothing: any failure removes every file written
    /// and every record inserted by this call before rethrowing.
    func restoreAll(_ payloads: [VaultBackup.ArtifactPayload]) throws {
        guard session.vaultKey != nil else { throw Failure.locked }
        var inserted: [ArtifactRecord] = []
        var written: [URL] = []
        do {
            for payload in payloads {
                // Same-id re-import (restoring a backup twice) keeps the
                // existing artifact — ids are stable across backup round trips.
                if let existing = store.artifactRecord(id: payload.id),
                   existing.deletedAt == nil { continue }
                let record = try insertArtifact(id: payload.id, ownerItemId: payload.ownerItemId,
                                                filename: payload.filename, utiType: payload.utiType,
                                                data: payload.data)
                inserted.append(record)
                written.append(fileURL(for: record))
            }
            try store.context.save()
        } catch {
            for url in written { try? FileManager.default.removeItem(at: url) }
            for record in inserted { store.context.delete(record) }
            try? store.context.save()
            throw error
        }
        for record in inserted {
            appendJournal(op: "restore", artifactID: record.id, path: record.relativePath)
        }
    }

    /// Seal + write + insert one artifact (no save — callers batch the save).
    private func insertArtifact(id: String, ownerItemId: String,
                                filename: String, utiType: String, data: Data) throws -> ArtifactRecord {
        guard let vaultKey = session.vaultKey else { throw Failure.locked }
        var dek = ArtifactCrypto.newDEK()
        defer { secureZero(&dek) }
        let envelope = try ArtifactCrypto.sealArtifact(
            plaintext: data, dek: dek, artifactID: id,
            ownerItemID: ownerItemId, purpose: ArtifactCrypto.purposeFile)
        let manifest = ArtifactManifest(filename: filename, utiType: utiType,
                                        plaintextByteCount: data.count,
                                        plaintextSHA256: ArtifactCrypto.sha256(data))
        let record = ArtifactRecord(
            id: id,
            ownerItemId: ownerItemId,
            wrappedDEK: try ArtifactCrypto.wrapDEK(dek, under: vaultKey,
                                                   artifactID: id, ownerItemID: ownerItemId),
            sealedManifest: try ArtifactCrypto.sealManifest(manifest, dek: dek,
                                                            artifactID: id, ownerItemID: ownerItemId),
            relativePath: "\(id).enc",
            byteCount: envelope.count,
            ciphertextHash: ArtifactCrypto.sha256(envelope))
        try envelope.write(to: fileURL(for: record), options: [.atomic, .completeFileProtection])
        store.context.insert(record)
        return record
    }

    // MARK: Recovery journal

    private struct JournalEntry: Codable {
        let op: String
        let artifactID: String
        let path: String
        let timestamp: Date
    }

    /// Append-only JSON-lines journal of lifecycle operations, so a crash
    /// between a file write and a record save leaves a trail `reconcile()`
    /// (or a human) can act on. Best-effort — journaling must never fail a
    /// vault operation.
    private func appendJournal(op: String, artifactID: String, path: String) {
        let entry = JournalEntry(op: op, artifactID: artifactID, path: path, timestamp: .now)
        guard var line = try? JSONEncoder().encode(entry) else { return }
        line.append(0x0A)
        if let handle = FileHandle(forWritingAtPath: journalURL.path) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: journalURL, options: [.atomic, .completeFileProtection])
        }
    }
}
