import CryptoKit
import XCTest
@testable import Vaultify

/// Kernel tests for the Quick View browser-handoff (QV-A1, Increment A).
/// SELF-CONSISTENCY tests (round-trip / mutation-sensitivity) — the
/// byte-for-byte BE-parity assertions against the frozen vectors live in
/// `QuickViewParityTests.swift` (GATE QV-1, met). These tests keep covering
/// what parity vectors don't: error classification, freshness/rollback
/// windows, and mutation-sensitivity of inputs the frozen vectors don't
/// enumerate.
@MainActor
final class QuickViewKernelTests: XCTestCase {

    // MARK: - SAS derivation

    func testSASIsDeterministicForFixedInputs() {
        let sessionID = Data("session-abc".utf8)
        let encHash = Data(repeating: 0x11, count: 32)
        let sigHash = Data(repeating: 0x22, count: 32)
        let first = QuickViewSAS.derive(sessionID: sessionID, encKeyHash: encHash, sigKeyHash: sigHash)
        let second = QuickViewSAS.derive(sessionID: sessionID, encKeyHash: encHash, sigKeyHash: sigHash)
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
        // Shape: "word word DD"
        let parts = try! XCTUnwrap(first).split(separator: " ")
        XCTAssertEqual(parts.count, 3)
        XCTAssertEqual(parts[2].count, 2)
        XCTAssertNotNil(Int(parts[2]))
    }

    func testSASDiffersWithDifferentKeyHash() {
        let sessionID = Data("session-abc".utf8)
        let encHash = Data(repeating: 0x11, count: 32)
        let sigHash = Data(repeating: 0x22, count: 32)
        let otherSigHash = Data(repeating: 0x33, count: 32)
        let a = QuickViewSAS.derive(sessionID: sessionID, encKeyHash: encHash, sigKeyHash: sigHash)
        let b = QuickViewSAS.derive(sessionID: sessionID, encKeyHash: encHash, sigKeyHash: otherSigHash)
        XCTAssertNotEqual(a, b)
    }

    func testSASFailsClosedOnWrongWordlistSize() {
        let result = QuickViewSAS.derive(sessionID: Data(), encKeyHash: Data(), sigKeyHash: Data(),
                                         words: ["only", "two"])
        XCTAssertNil(result)
    }

    // MARK: - Field manifest structural hash

    private func field(_ id: String, kind: QuickViewFieldKind = .username, value: String = "v",
                       concealed: Bool = false) -> QuickViewApprovedField {
        QuickViewApprovedField(stableID: id, kind: kind, label: "Label", value: value, concealed: concealed)
    }

    func testFieldManifestHashStableUnderValueChangeOnly() {
        let fields = [field("f1", value: "alpha"), field("f2", kind: .password, value: "beta")]
        let mutatedValues = [field("f1", value: "ALPHA-CHANGED"), field("f2", kind: .password, value: "BETA-CHANGED")]
        XCTAssertEqual(QuickViewFieldManifest.hash(orderedFields: fields),
                       QuickViewFieldManifest.hash(orderedFields: mutatedValues),
                       "manifest hash must be structural only — value-only changes must not affect it")
    }

    func testFieldManifestHashChangesWithKind() {
        let fields = [field("f1", kind: .username)]
        let changedKind = [field("f1", kind: .email)]
        XCTAssertNotEqual(QuickViewFieldManifest.hash(orderedFields: fields),
                          QuickViewFieldManifest.hash(orderedFields: changedKind))
    }

    func testFieldManifestHashChangesWithOrder() {
        let fields = [field("f1"), field("f2", kind: .password)]
        let reordered = [field("f2", kind: .password), field("f1")]
        XCTAssertNotEqual(QuickViewFieldManifest.hash(orderedFields: fields),
                          QuickViewFieldManifest.hash(orderedFields: reordered))
    }

    func testFieldManifestHashChangesWithConcealed() {
        let fields = [field("f1", concealed: false)]
        let concealed = [field("f1", concealed: true)]
        XCTAssertNotEqual(QuickViewFieldManifest.hash(orderedFields: fields),
                          QuickViewFieldManifest.hash(orderedFields: concealed))
    }

    // MARK: - Exposure resolver (full matrix, INV-QV-24)

    func testExposureMatrix() {
        // hidden — always denied, any assertion mode, any cohort.
        XCTAssertFalse(QuickViewExposureResolver.entryVisible(exposure: .hidden, assertionRequired: false, isBetaCohort: false))
        XCTAssertFalse(QuickViewExposureResolver.entryVisible(exposure: .hidden, assertionRequired: true, isBetaCohort: true))

        // beta — visible only to the gated beta cohort, independent of assertion mode.
        XCTAssertTrue(QuickViewExposureResolver.entryVisible(exposure: .beta, assertionRequired: false, isBetaCohort: true))
        XCTAssertTrue(QuickViewExposureResolver.entryVisible(exposure: .beta, assertionRequired: true, isBetaCohort: true))
        XCTAssertFalse(QuickViewExposureResolver.entryVisible(exposure: .beta, assertionRequired: false, isBetaCohort: false))
        XCTAssertFalse(QuickViewExposureResolver.entryVisible(exposure: .beta, assertionRequired: true, isBetaCohort: false))

        // ga — visible when assertion is required, any cohort.
        XCTAssertTrue(QuickViewExposureResolver.entryVisible(exposure: .ga, assertionRequired: true, isBetaCohort: false))
        XCTAssertTrue(QuickViewExposureResolver.entryVisible(exposure: .ga, assertionRequired: true, isBetaCohort: true))
        // ga + shadow: the beta cohort still sees it (already exercising it
        // under `beta`, promoting to `ga` is a no-op for them); a general
        // (non-beta) user fails closed (INV-QV-24).
        XCTAssertTrue(QuickViewExposureResolver.entryVisible(exposure: .ga, assertionRequired: false, isBetaCohort: true))
        XCTAssertFalse(QuickViewExposureResolver.entryVisible(exposure: .ga, assertionRequired: false, isBetaCohort: false))
    }

    // MARK: - Payload sealer (round-trip + mutation-sensitivity)

    private struct SealFixture {
        let browserPrivateKey = P256.KeyAgreement.PrivateKey()
        let plaintext = Data("quick-view-plaintext-payload".utf8)
        let browserEncKeyHash = Data(repeating: 0x44, count: 32)
        let browserSigKeyHash = Data(repeating: 0x55, count: 32)
        let sessionID = Data(repeating: 0x11, count: 32)
        let env = "staging"
        let approvalID = Data(repeating: 0x22, count: 32)
        let fieldManifestHash = Data(repeating: 0x66, count: 32)
        let issuedAt: Int64 = 1000
        let expiresAt: Int64 = 2000

        func seal() throws -> QuickViewPayloadSealer.SealedPayload {
            try QuickViewPayloadSealer.seal(
                plaintext: plaintext,
                browserEncPublicKey: browserPrivateKey.publicKey.x963Representation,
                browserEncKeyHash: browserEncKeyHash, browserSigKeyHash: browserSigKeyHash,
                sessionID: sessionID, env: env, approvalID: approvalID,
                fieldManifestHash: fieldManifestHash, issuedAt: issuedAt, expiresAt: expiresAt)
        }

        func open(_ sealed: QuickViewPayloadSealer.SealedPayload,
                  sessionID: Data? = nil, env: String? = nil, approvalID: Data? = nil,
                  fieldManifestHash: Data? = nil, browserEncKeyHash: Data? = nil) throws -> Data {
            try QuickViewPayloadSealer.open(
                sealed, browserEncPrivateKey: browserPrivateKey,
                browserEncKeyHash: browserEncKeyHash ?? self.browserEncKeyHash,
                browserSigKeyHash: browserSigKeyHash,
                sessionID: sessionID ?? self.sessionID, env: env ?? self.env,
                approvalID: approvalID ?? self.approvalID,
                fieldManifestHash: fieldManifestHash ?? self.fieldManifestHash,
                issuedAt: issuedAt, expiresAt: expiresAt)
        }
    }

    func testSealerRoundTripSucceeds() throws {
        let fixture = SealFixture()
        let sealed = try fixture.seal()
        let opened = try fixture.open(sealed)
        XCTAssertEqual(opened, fixture.plaintext)
    }

    /// The wire ciphertext is opaque: 12-byte nonce ‖ AES-GCM ciphertext ‖
    /// 16-byte tag, with no separate wire IV field.
    func testSealerCiphertextIsNoncePrependedOpaqueBlob() throws {
        let fixture = SealFixture()
        let sealed = try fixture.seal()
        XCTAssertEqual(sealed.ciphertext.count,
                       QuickViewPayloadSealer.nonceLength + fixture.plaintext.count + 16)
    }

    func testSealerRejectsWrongBrowserKey() throws {
        let fixture = SealFixture()
        let sealed = try fixture.seal()
        let wrongBrowserKey = P256.KeyAgreement.PrivateKey()
        XCTAssertThrowsError(try QuickViewPayloadSealer.open(
            sealed, browserEncPrivateKey: wrongBrowserKey,
            browserEncKeyHash: fixture.browserEncKeyHash, browserSigKeyHash: fixture.browserSigKeyHash,
            sessionID: fixture.sessionID, env: fixture.env, approvalID: fixture.approvalID,
            fieldManifestHash: fixture.fieldManifestHash, issuedAt: fixture.issuedAt, expiresAt: fixture.expiresAt))
    }

    func testSealerMutationSessionIDFailsOpen() throws {
        let fixture = SealFixture()
        let sealed = try fixture.seal()
        XCTAssertThrowsError(try fixture.open(sealed, sessionID: Data(repeating: 0x99, count: 32)))
    }

    func testSealerMutationEnvFailsOpen() throws {
        let fixture = SealFixture()
        let sealed = try fixture.seal()
        XCTAssertThrowsError(try fixture.open(sealed, env: "production"))
    }

    func testSealerMutationApprovalIDFailsOpen() throws {
        let fixture = SealFixture()
        let sealed = try fixture.seal()
        XCTAssertThrowsError(try fixture.open(sealed, approvalID: Data(repeating: 0x33, count: 32)))
    }

    func testSealerMutationFieldManifestHashFailsOpen() throws {
        let fixture = SealFixture()
        let sealed = try fixture.seal()
        XCTAssertThrowsError(try fixture.open(sealed, fieldManifestHash: Data(repeating: 0x99, count: 32)))
    }

    func testSealerMutationBrowserEncKeyHashFailsOpen() throws {
        let fixture = SealFixture()
        let sealed = try fixture.seal()
        XCTAssertThrowsError(try fixture.open(sealed, browserEncKeyHash: Data(repeating: 0x77, count: 32)))
    }

    // MARK: - Session envelope verifier

    private func signedEnvelopeData(env: String = "staging",
                                    sessionID: String = QuickViewWire.base64URLEncode(Data(repeating: 0x99, count: 32)),
                                    encKeyHash: Data = Data(repeating: 0x11, count: 32),
                                    sigKeyHash: Data = Data(repeating: 0x22, count: 32),
                                    issuedAt: Int64 = 0,
                                    expiresAt: Int64 = 1_000_000_000_000,
                                    key: P256.Signing.PrivateKey,
                                    mutateAfterSigning: ((inout [String: Any]) -> Void)? = nil) throws -> Data {
        // Wire fields are base64url (matches the live `/sessions` response).
        var json: [String: Any] = [
            "version": 1,
            "session_id": sessionID,
            "enc_key_hash": QuickViewWire.base64URLEncode(encKeyHash),
            "sig_key_hash": QuickViewWire.base64URLEncode(sigKeyHash),
            "browser_nonce": QuickViewWire.base64URLEncode(Data(repeating: 0xAA, count: 24)),
            "server_nonce": QuickViewWire.base64URLEncode(Data(repeating: 0xBB, count: 24)),
            "key_id": "test-key",
            "issued_at": issuedAt,
            "expires_at": expiresAt,
            "env": env,
        ]
        let unsigned = try JSONSerialization.data(withJSONObject: json)
        let envelope = try JSONDecoder().decode(QuickViewSessionEnvelope.self, from: unsigned)
        let signature = try key.signature(for: envelope.transcript)
        json["signature"] = signature.rawRepresentation.base64EncodedString()
        mutateAfterSigning?(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func resolver(_ key: P256.Signing.PrivateKey) -> (String) -> Data? {
        { keyID in keyID == "test-key" ? key.publicKey.x963Representation : nil }
    }

    func testEnvelopeVerifierAcceptsValidSignature() throws {
        let key = P256.Signing.PrivateKey()
        let sessionID = QuickViewWire.base64URLEncode(Data(repeating: 0x99, count: 32))
        let data = try signedEnvelopeData(sessionID: sessionID, key: key)
        let envelope = try QuickViewSessionEnvelopeVerifier.verify(
            envelopeData: data, resolveSignerKey: resolver(key), expectedEnv: "staging",
            expectedEncKeyHash: Data(repeating: 0x11, count: 32),
            expectedSigKeyHash: Data(repeating: 0x22, count: 32),
            now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(envelope.sessionID, sessionID)
    }

    func testEnvelopeVerifierRejectsTamperedPayload() throws {
        let key = P256.Signing.PrivateKey()
        let data = try signedEnvelopeData(key: key) { json in
            json["session_id"] = Data(repeating: 0xEE, count: 32).hexString   // post-signature mutation
        }
        XCTAssertThrowsError(try QuickViewSessionEnvelopeVerifier.verify(
            envelopeData: data, resolveSignerKey: resolver(key), expectedEnv: "staging",
            expectedEncKeyHash: Data(repeating: 0x11, count: 32),
            expectedSigKeyHash: Data(repeating: 0x22, count: 32),
            now: Date(timeIntervalSince1970: 1))) {
            XCTAssertEqual($0 as? QuickViewSessionEnvelopeVerifier.VerifyError, .badSignature)
        }
    }

    func testEnvelopeVerifierRejectsUnknownSignerKey() throws {
        let key = P256.Signing.PrivateKey()
        let data = try signedEnvelopeData(key: key)
        XCTAssertThrowsError(try QuickViewSessionEnvelopeVerifier.verify(
            envelopeData: data, resolveSignerKey: { _ in nil }, expectedEnv: "staging",
            expectedEncKeyHash: Data(repeating: 0x11, count: 32),
            expectedSigKeyHash: Data(repeating: 0x22, count: 32),
            now: Date(timeIntervalSince1970: 1))) {
            XCTAssertEqual($0 as? QuickViewSessionEnvelopeVerifier.VerifyError, .unknownKey("test-key"))
        }
    }

    func testEnvelopeVerifierRejectsWrongEnvironment() throws {
        let key = P256.Signing.PrivateKey()
        let data = try signedEnvelopeData(env: "production", key: key)
        XCTAssertThrowsError(try QuickViewSessionEnvelopeVerifier.verify(
            envelopeData: data, resolveSignerKey: resolver(key), expectedEnv: "staging",
            expectedEncKeyHash: Data(repeating: 0x11, count: 32),
            expectedSigKeyHash: Data(repeating: 0x22, count: 32),
            now: Date(timeIntervalSince1970: 1))) {
            XCTAssertEqual($0 as? QuickViewSessionEnvelopeVerifier.VerifyError, .wrongEnvironment("production"))
        }
    }

    func testEnvelopeVerifierRejectsExpired() throws {
        let key = P256.Signing.PrivateKey()
        let data = try signedEnvelopeData(issuedAt: 0, expiresAt: 1000, key: key)
        XCTAssertThrowsError(try QuickViewSessionEnvelopeVerifier.verify(
            envelopeData: data, resolveSignerKey: resolver(key), expectedEnv: "staging",
            expectedEncKeyHash: Data(repeating: 0x11, count: 32),
            expectedSigKeyHash: Data(repeating: 0x22, count: 32),
            now: Date(timeIntervalSince1970: 1_000_000))) {
            XCTAssertEqual($0 as? QuickViewSessionEnvelopeVerifier.VerifyError, .expired)
        }
    }

    func testEnvelopeVerifierRejectsKeyHashMismatch() throws {
        let key = P256.Signing.PrivateKey()
        let encHash = Data(repeating: 0x11, count: 32)
        let data = try signedEnvelopeData(encKeyHash: encHash, key: key)
        let wrongExpectedHash = Data(repeating: 0xFF, count: 32)
        XCTAssertThrowsError(try QuickViewSessionEnvelopeVerifier.verify(
            envelopeData: data, resolveSignerKey: resolver(key), expectedEnv: "staging",
            expectedEncKeyHash: wrongExpectedHash,
            expectedSigKeyHash: Data(repeating: 0x22, count: 32),
            now: Date(timeIntervalSince1970: 1))) {
            XCTAssertEqual($0 as? QuickViewSessionEnvelopeVerifier.VerifyError, .keyHashMismatch)
        }
    }
}
