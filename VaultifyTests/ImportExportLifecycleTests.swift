import CryptoKit
import XCTest
@testable import Vaultify

/// The pure decision layer under the Import and Export screens: what a file is
/// before it is opened, what an import actually did, and where an export's
/// plaintext lives while it waits to be shared.
final class ImportExportLifecycleTests: XCTestCase {

    // MARK: File classification

    private func envelopeJSON(version: Int = 2,
                              salt: Data = Data(repeating: 7, count: 16),
                              kdf: String = #"{"memoryCostKiB":65536,"timeCost":3,"parallelism":4}"#,
                              sealed: Data = Data(repeating: 9, count: 64)) -> Data {
        Data("""
        {"version":\(version),\
        "salt":"\(salt.base64EncodedString())",\
        "kdf":\(kdf),\
        "sealed":"\(sealed.base64EncodedString())"}
        """.utf8)
    }

    private func isEncrypted(_ outcome: ImportProbe.Outcome) -> Bool {
        if case .encrypted = outcome { return true }
        return false
    }

    private func isDamaged(_ outcome: ImportProbe.Outcome) -> Bool {
        if case .damaged = outcome { return true }
        return false
    }

    private func isUnsupported(_ outcome: ImportProbe.Outcome) -> Bool {
        if case .unsupported = outcome { return true }
        return false
    }

    func testWellFormedEnvelopeIsRecognisedAsEncrypted() {
        XCTAssertTrue(isEncrypted(ImportProbe.classify(envelopeJSON())))
    }

    func testShortSaltIsDamagedNotAWrongPassword() {
        // Argon2 answers ARGON2_SALT_TOO_SHORT here, which used to reach the
        // user as "couldn't decrypt" and read as a mistyped passphrase.
        let outcome = ImportProbe.classify(envelopeJSON(salt: Data(repeating: 1, count: 4)))
        XCTAssertTrue(isDamaged(outcome))
    }

    func testEmptySaltIsDamaged() {
        XCTAssertTrue(isDamaged(ImportProbe.classify(envelopeJSON(salt: Data()))))
    }

    func testOutOfPolicyKdfIsDamagedRatherThanParsedAsCSV() {
        // 4 GiB of Argon2 memory. The validating decoder refuses it, and the
        // file must not fall through to the CSV parser, which would happily
        // turn JSON braces and commas into junk items.
        let hostile = #"{"memoryCostKiB":4194304,"timeCost":3,"parallelism":4}"#
        XCTAssertTrue(isDamaged(ImportProbe.classify(envelopeJSON(kdf: hostile))))
    }

    func testEmptySealedPayloadIsDamaged() {
        XCTAssertTrue(isDamaged(ImportProbe.classify(envelopeJSON(sealed: Data()))))
    }

    func testUnrelatedJSONIsUnsupportedRatherThanParsedAsCSV() {
        XCTAssertTrue(isUnsupported(ImportProbe.classify(Data(#"{"hello":"world"}"#.utf8))))
        XCTAssertTrue(isUnsupported(ImportProbe.classify(Data("  [1,2,3]".utf8))))
    }

    func testBinaryFileIsUnsupported() {
        XCTAssertTrue(isUnsupported(ImportProbe.classify(Data([0xFF, 0xFE, 0x00, 0xFF]))))
    }

    func testCSVBecomesRows() {
        let csv = "name,username,password\nGitHub,me,secret\n"
        guard case let .rows(rows) = ImportProbe.classify(Data(csv.utf8)) else {
            return XCTFail("expected parsed rows")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.item.title, "GitHub")
    }

    func testHeaderOnlyCSVIsEmpty() {
        guard case .emptyCSV = ImportProbe.classify(Data("name,username,password\n".utf8)) else {
            return XCTFail("expected an empty CSV outcome")
        }
    }

    // MARK: Ceilings

    func testFileAndRowCeilingsBound() {
        XCTAssertTrue(ImportLimits.fits(fileByteCount: ImportLimits.maxFileBytes))
        XCTAssertFalse(ImportLimits.fits(fileByteCount: ImportLimits.maxFileBytes + 1))
        XCTAssertTrue(ImportLimits.fits(sealedByteCount: ImportLimits.maxSealedBytes))
        XCTAssertFalse(ImportLimits.fits(sealedByteCount: ImportLimits.maxSealedBytes + 1))
        XCTAssertTrue(ImportLimits.fits(items: ImportLimits.maxItems,
                                        passkeys: ImportLimits.maxPasskeys,
                                        artifacts: ImportLimits.maxArtifacts))
        XCTAssertFalse(ImportLimits.fits(items: ImportLimits.maxItems + 1, passkeys: 0, artifacts: 0))
        XCTAssertFalse(ImportLimits.fits(items: 0, passkeys: ImportLimits.maxPasskeys + 1, artifacts: 0))
        XCTAssertFalse(ImportLimits.fits(items: 0, passkeys: 0, artifacts: ImportLimits.maxArtifacts + 1))
    }

    func testThisAppsHeaviestLegalExportStillFitsThroughImport() {
        // Attachments base64 to roughly 1.34x inside the sealed payload and
        // roughly 1.78x in the finished file. A limit change on either side
        // that breaks the round trip fails here rather than at a user's restore.
        let sealed = Double(ExportLimits.maxArtifactBytes) * 1.34
        let file = Double(ExportLimits.maxArtifactBytes) * 1.78
        XCTAssertLessThan(sealed, Double(ImportLimits.maxSealedBytes))
        XCTAssertLessThan(file, Double(ImportLimits.maxFileBytes))
    }

    func testExportArtifactCeiling() {
        XCTAssertTrue(ExportLimits.fits(artifactBytes: ExportLimits.maxArtifactBytes))
        XCTAssertFalse(ExportLimits.fits(artifactBytes: ExportLimits.maxArtifactBytes + 1))
        XCTAssertEqual(ExportLimits.maxArtifactMegabytes, 48)
    }

    // MARK: Level-2 stranding

    func testNoSealedValuesNeverWarns() {
        XCTAssertNil(Level2ImportWarning.evaluate(sealedFieldCount: 0, hasWrap: false, adoption: nil))
        XCTAssertNil(Level2ImportWarning.evaluate(sealedFieldCount: 0, hasWrap: true,
                                                  adoption: .skippedDeviceHasOwnWrap))
    }

    func testSealedValuesWithoutAWrapWarn() {
        XCTAssertEqual(Level2ImportWarning.evaluate(sealedFieldCount: 3, hasWrap: false, adoption: nil),
                       .noWrapInBackup)
    }

    func testAdoptedWrapDoesNotWarn() {
        XCTAssertNil(Level2ImportWarning.evaluate(sealedFieldCount: 3, hasWrap: true, adoption: .adopted))
    }

    func testCollisionAndRefusalEachGetTheirOwnWarning() {
        XCTAssertEqual(Level2ImportWarning.evaluate(sealedFieldCount: 1, hasWrap: true,
                                                    adoption: .skippedDeviceHasOwnWrap),
                       .deviceHasOwnWrap)
        XCTAssertEqual(Level2ImportWarning.evaluate(sealedFieldCount: 1, hasWrap: true,
                                                    adoption: .refusedInvalidPolicy),
                       .wrapRefused)
    }

    // MARK: Honest reporting

    func testAFullRestoreIsComplete() {
        var report = ImportReport()
        report.itemsTotal = 10
        report.itemsImported = 10
        report.artifactsTotal = 2
        report.artifactsImported = 2
        report.passkeysTotal = 1
        report.passkeysImported = 1
        XCTAssertTrue(report.isComplete)
        XCTAssertNil(report.level2Warning)
        XCTAssertEqual(report.recordsImported, 11)
    }

    func testArtifactsFailingAloneIsNotASuccess() {
        var report = ImportReport()
        report.itemsTotal = 10
        report.itemsImported = 10
        report.artifactsTotal = 2
        report.artifactsImported = 0
        XCTAssertFalse(report.isComplete)
    }

    func testSkippedRowsAreNotASuccess() {
        var report = ImportReport()
        report.itemsTotal = 10
        report.itemsImported = 8
        XCTAssertFalse(report.isComplete)
    }

    func testStrandedSealedValuesAreNotASuccess() {
        var report = ImportReport()
        report.itemsTotal = 4
        report.itemsImported = 4
        report.sealedFieldCount = 2
        report.hasLevel2Wrap = true
        report.level2 = .skippedDeviceHasOwnWrap
        XCTAssertFalse(report.isComplete)
        XCTAssertEqual(report.level2Warning, .deviceHasOwnWrap)
    }

    // MARK: Failure classification

    func testAuthenticationFailureIsAWrongPassword() {
        XCTAssertEqual(ImportFailureMessage.text(for: CryptoKitError.authenticationFailure),
                       ImportFailureMessage.wrongPassword)
    }

    func testFileLevelFailuresAreNotBlamedOnThePassword() {
        let decoding = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [], debugDescription: "bad"))
        XCTAssertEqual(ImportFailureMessage.text(for: decoding), ImportFailureMessage.damaged)
        XCTAssertEqual(ImportFailureMessage.text(for: VaultBackup.BackupFailure.artifactUnsafePath),
                       ImportFailureMessage.damaged)
        XCTAssertEqual(ImportFailureMessage.text(for: VaultBackup.BackupFailure.artifactCorrupt),
                       ImportFailureMessage.damaged)
        XCTAssertEqual(ImportFailureMessage.text(for: Argon2.Failure.hashFailed(code: -8, message: "salt too short")),
                       ImportFailureMessage.damaged)
        XCTAssertEqual(ImportFailureMessage.text(for: AESGCM.Failure.invalidKeyLength),
                       ImportFailureMessage.damaged)
        XCTAssertNotEqual(ImportFailureMessage.damaged, ImportFailureMessage.wrongPassword)
    }

    // MARK: Export temp files

    func testEachExportGetsItsOwnDirectoryAndReplacesThePrevious() throws {
        defer { ExportTempFiles.purge() }
        let first = try ExportTempFiles.write(Data("one".utf8), name: "loox-export.csv")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        let second = try ExportTempFiles.write(Data("two".utf8), name: "loox-export.csv")
        XCTAssertNotEqual(first, second)
        // The fixed filename used to make every export overwrite the same path
        // and outlive its screen; only the newest one may exist now.
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        let directories = try FileManager.default.contentsOfDirectory(
            at: ExportTempFiles.root, includingPropertiesForKeys: nil)
        XCTAssertEqual(directories.count, 1)
    }

    func testPurgeRemovesEveryExport() throws {
        let url = try ExportTempFiles.write(Data("plaintext vault".utf8), name: "loox-export.csv")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        ExportTempFiles.purge()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: ExportTempFiles.root.path))
    }

    func testPurgeOnAnEmptyRootIsHarmless() {
        ExportTempFiles.purge()
        ExportTempFiles.purge()
        XCTAssertFalse(FileManager.default.fileExists(atPath: ExportTempFiles.root.path))
    }
}
