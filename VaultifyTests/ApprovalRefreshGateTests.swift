import XCTest
@testable import Vaultify

/// State machine of the owner-side request-scan gate: push marks dirty,
/// triggers are cheap no-ops when clean, the first pass per launch always
/// scans, and consume-then-restore keeps a mid-pass push alive and an
/// offline pass retryable. Pure struct — no coordinator, no CloudKit.
@MainActor
final class ApprovalRefreshGateTests: XCTestCase {

    func testColdLaunchAlwaysScans() {
        // Pushes are best-effort: a request written while the app was dead
        // must still surface on the first trigger of the process lifetime.
        let gate = RequestScanGate()
        XCTAssertTrue(gate.shouldScan(inboxEmpty: true))
    }

    func testCleanGateWithEmptyInboxSkips() {
        var gate = RequestScanGate()
        gate.beginScan() // successful cold-launch pass consumed the flag
        XCTAssertFalse(gate.shouldScan(inboxEmpty: true))
    }

    func testNonEmptyInboxAlwaysScans() {
        // The pass is what expires TTL'd entries and drops zone-gone
        // records — a shown request must keep forcing rescans.
        var gate = RequestScanGate()
        gate.beginScan()
        XCTAssertTrue(gate.shouldScan(inboxEmpty: false))
    }

    func testPushMarksDirtyAndNextTriggerScans() {
        var gate = RequestScanGate()
        gate.beginScan()
        gate.markDirty()
        XCTAssertTrue(gate.shouldScan(inboxEmpty: true))
    }

    func testFailedScanRestoresTheFlag() {
        // Offline/transient pass: the next trigger must retry instead of
        // silently going stale until the next push.
        var gate = RequestScanGate()
        XCTAssertTrue(gate.shouldScan(inboxEmpty: true))
        gate.beginScan()
        gate.scanFailed()
        XCTAssertTrue(gate.shouldScan(inboxEmpty: true))
    }

    func testPushArrivingMidPassSurvivesASuccessfulPass() {
        // Consume-then-restore: the flag is cleared BEFORE the scan starts,
        // so a push landing during the pass re-dirties it and the follow-up
        // trigger rescans — clearing after the loop would swallow it.
        var gate = RequestScanGate()
        gate.beginScan()          // pass starts
        gate.markDirty()          // push lands mid-pass
        // pass completes successfully: nothing clears the flag again
        XCTAssertTrue(gate.shouldScan(inboxEmpty: true))
    }

    func testSuccessfulPassAfterPushGoesQuietAgain() {
        var gate = RequestScanGate()
        gate.beginScan()
        gate.markDirty()
        gate.beginScan()          // the follow-up pass consumes the push
        XCTAssertFalse(gate.shouldScan(inboxEmpty: true))
    }
}
