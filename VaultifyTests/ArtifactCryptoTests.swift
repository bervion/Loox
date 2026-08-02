import Foundation
import XCTest
@testable import Vaultify

/// The artifact crypto contract: every seal is AAD-bound to its artifact id,
/// owner, and purpose — a blob or key moved to any other slot must fail
/// authentication, an oversized buffer must be refused from its byte count
/// alone, and the versioned envelope must reject bytes it doesn't understand.
final class ArtifactCryptoTests: XCTestCase {

    private let artifactID = "11111111-2222-3333-4444-555555555555"
    private let ownerItemID = "66666666-7777-8888-9999-000000000000"
    private let plaintext = Data("artifact payload bytes".utf8)

    private func vaultKey() -> SecureBytes { SecureBytes([UInt8](repeating: 0x2a, count: 32)) }

    // MARK: Blob round trip

    func testSealOpenRoundTripsExactBytes() throws {
        let dek = ArtifactCrypto.newDEK()
        let envelope = try ArtifactCrypto.sealArtifact(
            plaintext: plaintext, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile)

        XCTAssertEqual(envelope.first, ArtifactCrypto.envelopeVersion)
        let opened = try ArtifactCrypto.openArtifact(
            envelope: envelope, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile)
        XCTAssertEqual(opened, plaintext)
    }

    func testEmptyPlaintextRoundTrips() throws {
        let dek = ArtifactCrypto.newDEK()
        let envelope = try ArtifactCrypto.sealArtifact(
            plaintext: Data(), dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile)
        XCTAssertEqual(try ArtifactCrypto.openArtifact(
            envelope: envelope, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile), Data())
    }

    // MARK: AAD binding (the whole point of the design)

    func testOpenFailsWhenAnyAADComponentIsSwapped() throws {
        let dek = ArtifactCrypto.newDEK()
        let envelope = try ArtifactCrypto.sealArtifact(
            plaintext: plaintext, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile)

        XCTAssertThrowsError(try ArtifactCrypto.openArtifact(
            envelope: envelope, dek: dek, artifactID: "other-artifact",
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile),
            "a blob copied into another artifact slot must not decrypt")
        XCTAssertThrowsError(try ArtifactCrypto.openArtifact(
            envelope: envelope, dek: dek, artifactID: artifactID,
            ownerItemID: "other-item", purpose: ArtifactCrypto.purposeFile),
            "a blob re-parented to another item must not decrypt")
        XCTAssertThrowsError(try ArtifactCrypto.openArtifact(
            envelope: envelope, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeBackup),
            "a blob replayed in a different role must not decrypt")
    }

    func testTruncatedEnvelopeFails() throws {
        let dek = ArtifactCrypto.newDEK()
        let envelope = try ArtifactCrypto.sealArtifact(
            plaintext: plaintext, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile)

        XCTAssertThrowsError(try ArtifactCrypto.openArtifact(
            envelope: envelope.dropLast(), dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile))
        XCTAssertThrowsError(try ArtifactCrypto.openArtifact(
            envelope: Data(), dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile))
    }

    func testUnknownEnvelopeVersionIsRejectedNotGuessed() throws {
        let dek = ArtifactCrypto.newDEK()
        var envelope = try ArtifactCrypto.sealArtifact(
            plaintext: plaintext, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile)
        envelope[0] = 0x7F

        XCTAssertThrowsError(try ArtifactCrypto.openArtifact(
            envelope: envelope, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile)) { error in
            XCTAssertEqual(error as? ArtifactCrypto.Failure, .unsupportedVersion(0x7F))
        }
    }

    // MARK: Size ceiling

    func testOversizePlaintextIsRejectedBeforeSealing() {
        let dek = ArtifactCrypto.newDEK()
        let oversize = Data(count: ArtifactCrypto.maxPlaintextBytes + 1)

        XCTAssertThrowsError(try ArtifactCrypto.sealArtifact(
            plaintext: oversize, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile)) { error in
            XCTAssertEqual(error as? ArtifactCrypto.Failure,
                           .oversize(byteCount: ArtifactCrypto.maxPlaintextBytes + 1))
        }
    }

    func testOversizeEnvelopeIsRejectedBeforeOpening() {
        let dek = ArtifactCrypto.newDEK()
        let oversize = Data(count: ArtifactCrypto.maxEnvelopeBytes + 1)

        XCTAssertThrowsError(try ArtifactCrypto.openArtifact(
            envelope: oversize, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile)) { error in
            XCTAssertEqual(error as? ArtifactCrypto.Failure,
                           .oversize(byteCount: ArtifactCrypto.maxEnvelopeBytes + 1))
        }
    }

    func testCeilingBoundaryPlaintextSealsAndOpens() throws {
        let dek = ArtifactCrypto.newDEK()
        let exact = Data(count: ArtifactCrypto.maxPlaintextBytes)
        let envelope = try ArtifactCrypto.sealArtifact(
            plaintext: exact, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile)
        XCTAssertEqual(envelope.count, ArtifactCrypto.maxEnvelopeBytes)
        XCTAssertEqual(try ArtifactCrypto.openArtifact(
            envelope: envelope, dek: dek, artifactID: artifactID,
            ownerItemID: ownerItemID, purpose: ArtifactCrypto.purposeFile).count,
            ArtifactCrypto.maxPlaintextBytes)
    }

    // MARK: DEK wrap

    func testDEKWrapRoundTrip() throws {
        let key = vaultKey()
        let dek = ArtifactCrypto.newDEK()
        let wrapped = try ArtifactCrypto.wrapDEK(dek, under: key,
                                                 artifactID: artifactID, ownerItemID: ownerItemID)
        XCTAssertEqual(try ArtifactCrypto.unwrapDEK(wrapped, under: key,
                                                    artifactID: artifactID, ownerItemID: ownerItemID), dek)
    }

    func testDEKUnwrapFailsUnderWrongVaultKeyOrSwappedAAD() throws {
        let key = vaultKey()
        let dek = ArtifactCrypto.newDEK()
        let wrapped = try ArtifactCrypto.wrapDEK(dek, under: key,
                                                 artifactID: artifactID, ownerItemID: ownerItemID)

        let wrongKey = SecureBytes([UInt8](repeating: 0x3b, count: 32))
        XCTAssertThrowsError(try ArtifactCrypto.unwrapDEK(wrapped, under: wrongKey,
                                                          artifactID: artifactID, ownerItemID: ownerItemID))
        XCTAssertThrowsError(try ArtifactCrypto.unwrapDEK(wrapped, under: key,
                                                          artifactID: "other-artifact", ownerItemID: ownerItemID))
        XCTAssertThrowsError(try ArtifactCrypto.unwrapDEK(wrapped, under: key,
                                                          artifactID: artifactID, ownerItemID: "other-item"))
    }

    // MARK: Manifest

    func testManifestRoundTripsAndIsAADBound() throws {
        let dek = ArtifactCrypto.newDEK()
        let manifest = ArtifactManifest(filename: "passport.pdf",
                                        utiType: "com.adobe.pdf",
                                        plaintextByteCount: plaintext.count,
                                        plaintextSHA256: ArtifactCrypto.sha256(plaintext))
        let sealed = try ArtifactCrypto.sealManifest(manifest, dek: dek,
                                                     artifactID: artifactID, ownerItemID: ownerItemID)

        XCTAssertEqual(try ArtifactCrypto.openManifest(sealed, dek: dek,
                                                       artifactID: artifactID, ownerItemID: ownerItemID),
                       manifest)
        XCTAssertThrowsError(try ArtifactCrypto.openManifest(sealed, dek: dek,
                                                             artifactID: "other-artifact",
                                                             ownerItemID: ownerItemID))
    }

    // MARK: Hash helper (known-answer)

    func testSHA256KnownAnswer() {
        XCTAssertEqual(
            ArtifactCrypto.sha256(Data("abc".utf8)).map { String(format: "%02x", $0) }.joined(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
