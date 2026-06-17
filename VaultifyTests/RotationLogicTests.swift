import XCTest
@testable import Vaultify

/// Unit tests for `RotationStatus.evaluate` boundary conditions.
/// All tests inject `now` for determinism — no real clock dependency.
final class RotationLogicTests: XCTestCase {

    // MARK: Helpers

    private let anchor = Date(timeIntervalSinceReferenceDate: 0) // 2001-01-01T00:00:00Z

    /// Returns a date `days` after `anchor`.
    private func date(_ days: Int) -> Date {
        anchor.addingTimeInterval(Double(days) * 86_400)
    }

    /// Evaluate with a 30-day cadence, password changed at `anchor`, simulating
    /// `days` having elapsed since then.
    private func eval30(daysSince: Int, changedAt: Date? = nil) -> RotationStatus {
        let changed = changedAt ?? anchor
        let now = date(daysSince)
        return RotationStatus.evaluate(
            rotateDays: 30,
            passwordChangedAt: changed,
            createdAt: anchor,
            now: now)
    }

    // MARK: Cadence = 30 days

    func testOverdueWhenDueIsZero() {
        // Exactly at the deadline (30 days elapsed) → due = 0 → overdue.
        let status = eval30(daysSince: 30)
        XCTAssertEqual(status.state, .overdue)
        XCTAssertEqual(status.tone, .destructive)
    }

    func testOverdueWhenPastDeadline() {
        // 33 days elapsed → due = -3 → overdue.
        let status = eval30(daysSince: 33)
        XCTAssertEqual(status.state, .overdue)
        XCTAssertEqual(status.tone, .destructive)
    }

    func testSoonWhenDueIsFive() {
        // 25 days elapsed → due = 5 → soon (boundary: ≤ 5 is soon).
        let status = eval30(daysSince: 25)
        XCTAssertEqual(status.state, .soon)
        XCTAssertEqual(status.tone, .warning)
    }

    func testSoonWhenDueIsOne() {
        // 29 days elapsed → due = 1 → soon.
        let status = eval30(daysSince: 29)
        XCTAssertEqual(status.state, .soon)
        XCTAssertEqual(status.tone, .warning)
    }

    func testOkWhenDueIsSix() {
        // 24 days elapsed → due = 6 → ok (boundary: > 5 is ok).
        let status = eval30(daysSince: 24)
        XCTAssertEqual(status.state, .ok)
        XCTAssertEqual(status.tone, .neutral)
    }

    func testOkWhenFresh() {
        // 0 days elapsed → due = 30 → ok.
        let status = eval30(daysSince: 0)
        XCTAssertEqual(status.state, .ok)
        XCTAssertEqual(status.tone, .neutral)
    }

    // MARK: No cadence (rotateDays = 0)

    func testStaleAtExactly180Days() {
        // No cadence, 180 days elapsed → stale.
        let status = RotationStatus.evaluate(
            rotateDays: 0,
            passwordChangedAt: anchor,
            createdAt: anchor,
            now: date(180))
        XCTAssertEqual(status.state, .stale)
        XCTAssertEqual(status.tone, .warning)
    }

    func testStaleAt181Days() {
        let status = RotationStatus.evaluate(
            rotateDays: 0,
            passwordChangedAt: anchor,
            createdAt: anchor,
            now: date(181))
        XCTAssertEqual(status.state, .stale)
    }

    func testOkNoCadenceFresh() {
        // No cadence, only 10 days elapsed → ok.
        let status = RotationStatus.evaluate(
            rotateDays: 0,
            passwordChangedAt: anchor,
            createdAt: anchor,
            now: date(10))
        XCTAssertEqual(status.state, .ok)
        XCTAssertEqual(status.tone, .neutral)
    }

    func testOkNoCadenceAt179Days() {
        // Boundary: 179 days is NOT stale.
        let status = RotationStatus.evaluate(
            rotateDays: 0,
            passwordChangedAt: anchor,
            createdAt: anchor,
            now: date(179))
        XCTAssertEqual(status.state, .ok)
    }

    // MARK: passwordChangedAt nil → falls back to createdAt

    func testNilPasswordChangedAtUsesCreatedAt() {
        // createdAt = anchor, no explicit passwordChangedAt, 33 days elapsed with 30-day cadence.
        let status = RotationStatus.evaluate(
            rotateDays: 30,
            passwordChangedAt: nil,
            createdAt: anchor,
            now: date(33))
        XCTAssertEqual(status.state, .overdue,
                       "nil passwordChangedAt should fall back to createdAt as baseline")
    }

    func testNilPasswordChangedAtNoCadenceStale() {
        // No cadence, nil changed, createdAt used, 200 days → stale.
        let status = RotationStatus.evaluate(
            rotateDays: 0,
            passwordChangedAt: nil,
            createdAt: anchor,
            now: date(200))
        XCTAssertEqual(status.state, .stale)
    }

    // MARK: attentionReason

    func testAttentionReasonOverdudePriorityOverWeak() {
        let overdue = RotationStatus.evaluate(
            rotateDays: 30, passwordChangedAt: anchor, createdAt: anchor, now: date(40))
        let reason = RotationStatus.attentionReason(status: overdue, isWeak: true)
        XCTAssertEqual(reason, .overdue, "Overdue takes priority over weak password")
    }

    func testAttentionReasonWeakWhenOk() {
        let ok = RotationStatus.evaluate(
            rotateDays: 30, passwordChangedAt: anchor, createdAt: anchor, now: date(5))
        let reason = RotationStatus.attentionReason(status: ok, isWeak: true)
        XCTAssertEqual(reason, .weak, "Weak password should surface when rotation is ok")
    }

    func testAttentionReasonNilWhenOkAndStrong() {
        let ok = RotationStatus.evaluate(
            rotateDays: 30, passwordChangedAt: anchor, createdAt: anchor, now: date(5))
        let reason = RotationStatus.attentionReason(status: ok, isWeak: false)
        XCTAssertNil(reason, "No attention when rotation ok and password strong")
    }

    func testAttentionReasonSoon() {
        let soon = RotationStatus.evaluate(
            rotateDays: 30, passwordChangedAt: anchor, createdAt: anchor, now: date(27))
        let reason = RotationStatus.attentionReason(status: soon, isWeak: false)
        XCTAssertEqual(reason, .soon)
    }

    func testAttentionReasonStale() {
        let stale = RotationStatus.evaluate(
            rotateDays: 0, passwordChangedAt: anchor, createdAt: anchor, now: date(200))
        let reason = RotationStatus.attentionReason(status: stale, isWeak: false)
        XCTAssertEqual(reason, .stale)
    }
}
