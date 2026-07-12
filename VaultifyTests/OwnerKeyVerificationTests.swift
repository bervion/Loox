import XCTest
@testable import Vaultify

/// Transition rules of the recipient's safety-code trust decision: a missing
/// marker on a new pin reads as pending (fail closed), confirmed/skipped are
/// terminal (never re-prompt), and the one-shot backfill grandfathers only
/// zones that were already pinned before the gate existed.
@MainActor
final class OwnerKeyVerificationTests: XCTestCase {

    // MARK: Decision semantics

    func testPendingWithholdsUseAndKeepsPrompting() {
        XCTAssertFalse(OwnerKeyVerification.pending.isDecided)
        XCTAssertFalse(OwnerKeyVerification.pending.allowsUse)
    }

    func testConfirmedAndSkippedAreTerminalAndAllowUse() {
        // An explicit skip is a recorded decision — it unlocks use exactly
        // like a confirm and must never re-nag.
        for decided in [OwnerKeyVerification.confirmed, .skipped] {
            XCTAssertTrue(decided.isDecided)
            XCTAssertTrue(decided.allowsUse)
        }
    }

    // MARK: Storage stability

    func testRawValuesAreStable() {
        // The marker is persisted by rawValue in the Keychain — renaming a
        // case would silently reset every recorded decision to pending.
        XCTAssertEqual(OwnerKeyVerification(rawValue: "pending"), .pending)
        XCTAssertEqual(OwnerKeyVerification(rawValue: "confirmed"), .confirmed)
        XCTAssertEqual(OwnerKeyVerification(rawValue: "skipped"), .skipped)
        XCTAssertNil(OwnerKeyVerification(rawValue: "trusted"))
    }

    // MARK: Backfill rule (pre-gate shares)

    func testBackfillGrandfathersPinnedZoneWithoutMarker() {
        // Pinned before the gate existed and in active use → confirmed once,
        // never retro-prompted.
        XCTAssertEqual(OwnerKeyVerification.backfillState(hasPin: true, existing: nil),
                       .confirmed)
    }

    func testBackfillLeavesUnpinnedZoneUnmarked() {
        // No pin yet → no marker; the normal pending path applies when the
        // pin lands. Backfilling confirmed here would default-trust a share
        // the user has never seen.
        XCTAssertNil(OwnerKeyVerification.backfillState(hasPin: false, existing: nil))
    }

    func testBackfillNeverOverwritesAnExistingMarker() {
        // Idempotence across re-runs (reinstall keeps Keychain markers but
        // resets the one-shot flag): whatever was recorded stays recorded.
        XCTAssertEqual(OwnerKeyVerification.backfillState(hasPin: true, existing: .pending),
                       .pending)
        XCTAssertEqual(OwnerKeyVerification.backfillState(hasPin: true, existing: .skipped),
                       .skipped)
        XCTAssertEqual(OwnerKeyVerification.backfillState(hasPin: true, existing: .confirmed),
                       .confirmed)
    }
}
