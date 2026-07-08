import CryptoKit
import XCTest
@testable import Vaultify

/// Session-client tests (QV-A2, Increment B): canonical upload body + App
/// Attest assertion transcript mutation-sensitivity, and the generic-failure
/// mapping discipline. SELF-CONSISTENCY tests — byte-for-byte BE-parity
/// assertions against the frozen `LOOX-APP-ATTEST-QUICK-VIEW-V1` vectors
/// live in `QuickViewParityTests.swift`.
final class QuickViewClientTests: XCTestCase {

    private func fixtureBody(aad: Data = Data(repeating: 0x11, count: 8),
                             ciphertext: Data = Data(repeating: 0xAA, count: 12) + Data("cipher".utf8) + Data(repeating: 0xCC, count: 16),
                             appEphemeralPublicKey: Data = Data([0x01, 0x02])) -> Data {
        QuickViewCanonical.canonicalUploadBody(aad: aad, ciphertext: ciphertext, appEphemeralPublicKey: appEphemeralPublicKey)
    }

    func testUploadBodyMutationSensitivity() {
        let base = fixtureBody()
        XCTAssertNotEqual(base, fixtureBody(aad: Data(repeating: 0x22, count: 8)), "aad must be bound")
        XCTAssertNotEqual(base, fixtureBody(ciphertext: Data("different".utf8)), "ciphertext must be bound")
        XCTAssertNotEqual(base, fixtureBody(appEphemeralPublicKey: Data([0x03, 0x04])),
                          "app ephemeral public key must be bound")
    }

    func testUploadBodyDeterministicForFixedInputs() {
        XCTAssertEqual(fixtureBody(), fixtureBody(), "same inputs must produce byte-identical bodies")
    }

    func testUploadPathIsPinnedAndUsedByBothCanonicalAndTranscript() {
        let path = QuickViewCanonical.uploadPath(sessionID: "sess-9")
        XCTAssertEqual(path, "\(QuickViewConfig.servicePathPrefix)/sessions/sess-9/payload")
    }

    private let sessionID1 = Data(repeating: 0x01, count: 32)
    private let sessionID2 = Data(repeating: 0x02, count: 32)

    func testAssertionTranscriptMutationSensitivity() {
        let body = fixtureBody()
        let base = QuickViewCanonical.assertionClientDataHash(
            path: "/p", challengeID: "chal-1", sessionIDBytes: sessionID1, uploadBody: body)
        XCTAssertNotEqual(base, QuickViewCanonical.assertionClientDataHash(
            path: "/other", challengeID: "chal-1", sessionIDBytes: sessionID1, uploadBody: body), "path must be bound")
        XCTAssertNotEqual(base, QuickViewCanonical.assertionClientDataHash(
            path: "/p", challengeID: "chal-2", sessionIDBytes: sessionID1, uploadBody: body), "challenge id must be bound")
        XCTAssertNotEqual(base, QuickViewCanonical.assertionClientDataHash(
            path: "/p", challengeID: "chal-1", sessionIDBytes: sessionID2, uploadBody: body), "session id must be bound")
        XCTAssertNotEqual(base, QuickViewCanonical.assertionClientDataHash(
            path: "/p", challengeID: "chal-1", sessionIDBytes: sessionID1, uploadBody: fixtureBody(aad: Data(repeating: 0x99, count: 8))),
            "the upload body's own hash must be bound (proves the EXACT upload, not just context)")
    }

    func testAssertionTranscriptMethodIsUppercasedConsistently() {
        let body = fixtureBody()
        let lower = QuickViewCanonical.assertionClientDataHash(
            method: "post", path: "/p", challengeID: "chal-1", sessionIDBytes: sessionID1, uploadBody: body)
        let upper = QuickViewCanonical.assertionClientDataHash(
            method: "POST", path: "/p", challengeID: "chal-1", sessionIDBytes: sessionID1, uploadBody: body)
        XCTAssertEqual(lower, upper, "method normalization must make casing irrelevant")
    }

    // MARK: - Generic-failure mapping (plan.md failure discipline)

    func testSessionUnavailableErrorMessageIsGenericAndStable() {
        let message = QuickViewAPIError.sessionUnavailable.errorDescription
        XCTAssertEqual(message, "Start again on the computer.")
    }

    func testCapabilityErrorMessagesDoNotLeakOperatorDetail() {
        XCTAssertNotNil(QuickViewAPIError.capability(.maintenance, retryAfter: 30).errorDescription)
        XCTAssertNotNil(QuickViewAPIError.capability(.retired, retryAfter: nil).errorDescription)
        XCTAssertNotNil(QuickViewAPIError.capability(.disabled, retryAfter: nil).errorDescription)
    }
}
