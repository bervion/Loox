import XCTest
@testable import Vaultify

/// RFC 6238/4226 behavior of `TOTPGenerator`, pinned so the otpauth `period`
/// contract the countdown UIs rely on (rings, expiry warnings) and the
/// malformed-URI hardening cannot regress silently.
final class TOTPGeneratorTests: XCTestCase {
    /// RFC 6238 Appendix B secret ("12345678901234567890") in base32.
    private let rfcSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"

    private func otpauth(_ query: String) -> String {
        "otpauth://totp/Example:alice?secret=\(rfcSecret)&\(query)"
    }

    // MARK: period(forStoredValue:)

    func testPeriodDefaultsTo30ForBareSecret() {
        XCTAssertEqual(TOTPGenerator.period(forStoredValue: rfcSecret), 30)
    }

    func testPeriodDefaultsTo30WhenURIOmitsIt() {
        XCTAssertEqual(TOTPGenerator.period(forStoredValue: otpauth("issuer=Example")), 30)
    }

    func testPeriodHonorsOtpauthParameter() {
        XCTAssertEqual(TOTPGenerator.period(forStoredValue: otpauth("period=60")), 60)
    }

    func testInvalidPeriodFallsBackTo30() {
        // period ≤ 0 would divide by zero in the counter math — a scanned QR is
        // untrusted input, so it must degrade to the RFC default, not trap.
        XCTAssertEqual(TOTPGenerator.period(forStoredValue: otpauth("period=0")), 30)
        XCTAssertEqual(TOTPGenerator.period(forStoredValue: otpauth("period=-5")), 30)
        XCTAssertNotNil(TOTPGenerator.code(forStoredValue: otpauth("period=0"),
                                           date: Date(timeIntervalSince1970: 59)))
    }

    // MARK: Code generation

    func testRFC6238KnownAnswer() {
        // RFC 6238 Appendix B: T = 59s, SHA-1, 8 digits → 94287082.
        XCTAssertEqual(TOTPGenerator.code(secretBase32: rfcSecret, digits: 8,
                                          date: Date(timeIntervalSince1970: 59)),
                       "94287082")
    }

    func testCustomPeriodWindowsShareCounter() {
        // With period=60 the whole first minute is counter 0 (RFC 4226 HOTP(0)
        // = 755224); the second minute is counter 1 (287082). A hardcoded 30
        // would have rotated the code at t = 30.
        let uri = otpauth("period=60")
        XCTAssertEqual(TOTPGenerator.code(forStoredValue: uri, date: Date(timeIntervalSince1970: 59)), "755224")
        XCTAssertEqual(TOTPGenerator.code(forStoredValue: uri, date: Date(timeIntervalSince1970: 61)), "287082")
    }

    func testOversizedDigitsClampToUInt32SafeCeiling() {
        // digits=20 would overflow the UInt32 modulus — clamped to 9 (RFC 4226
        // HOTP(0) full 9-digit truncation = 284755224), not a trap.
        let code = TOTPGenerator.code(forStoredValue: otpauth("digits=20&period=60"),
                                      date: Date(timeIntervalSince1970: 59))
        XCTAssertEqual(code, "284755224")
    }

    // MARK: secondsRemaining

    func testSecondsRemainingHonorsPeriod() {
        XCTAssertEqual(TOTPGenerator.secondsRemaining(period: 60, date: Date(timeIntervalSince1970: 59)), 1)
        XCTAssertEqual(TOTPGenerator.secondsRemaining(period: 60, date: Date(timeIntervalSince1970: 60)), 60)
        XCTAssertEqual(TOTPGenerator.secondsRemaining(period: 30, date: Date(timeIntervalSince1970: 59)), 1)
        XCTAssertEqual(TOTPGenerator.secondsRemaining(period: 30, date: Date(timeIntervalSince1970: 30)), 30)
    }
}
