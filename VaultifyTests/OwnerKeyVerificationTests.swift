import XCTest
@testable import Vaultify

/// Transition rules of the recipient's trust decision: a missing marker reads
/// as pending (fail closed, withheld from AutoFill), every other state allows
/// use, stored decisions only ever move up the ranking, and the one-shot
/// backfill grandfathers only zones that were already pinned before any
/// decision was recorded.
@MainActor
final class OwnerKeyVerificationTests: XCTestCase {

    // MARK: Decision semantics

    func testPendingWithholdsUse() {
        XCTAssertFalse(OwnerKeyVerification.pending.isDecided)
        XCTAssertFalse(OwnerKeyVerification.pending.allowsUse)
    }

    func testEveryDecidedStateAllowsUse() {
        // Accepting a share from a named sender is a decision, exactly like an
        // out-of-band code comparison or an explicit skip.
        for decided in [OwnerKeyVerification.accepted, .confirmed, .skipped] {
            XCTAssertTrue(decided.isDecided)
            XCTAssertTrue(decided.allowsUse)
        }
    }

    // MARK: Monotonic decisions

    func testAnyDecisionSupersedesNothingRecorded() {
        for decision in [OwnerKeyVerification.accepted, .confirmed, .skipped] {
            XCTAssertTrue(decision.supersedes(nil))
            XCTAssertTrue(decision.supersedes(.pending))
        }
    }

    func testComparingTheCodeUpgradesAnAcceptedShare() {
        XCTAssertTrue(OwnerKeyVerification.confirmed.supersedes(.accepted))
        XCTAssertTrue(OwnerKeyVerification.confirmed.supersedes(.skipped))
    }

    func testAnAutomaticMarkerNeverUndoesAComparison() {
        // Accepting/skipping says less than a performed comparison, so it must
        // never overwrite one — nor should either replace the other.
        XCTAssertFalse(OwnerKeyVerification.accepted.supersedes(.confirmed))
        XCTAssertFalse(OwnerKeyVerification.skipped.supersedes(.confirmed))
        XCTAssertFalse(OwnerKeyVerification.accepted.supersedes(.skipped))
        XCTAssertFalse(OwnerKeyVerification.skipped.supersedes(.accepted))
        XCTAssertFalse(OwnerKeyVerification.pending.supersedes(nil))
    }

    // MARK: Storage stability

    func testRawValuesAreStable() {
        // The marker is persisted by rawValue in the Keychain — renaming a
        // case would silently reset every recorded decision to pending.
        XCTAssertEqual(OwnerKeyVerification(rawValue: "pending"), .pending)
        XCTAssertEqual(OwnerKeyVerification(rawValue: "accepted"), .accepted)
        XCTAssertEqual(OwnerKeyVerification(rawValue: "confirmed"), .confirmed)
        XCTAssertEqual(OwnerKeyVerification(rawValue: "skipped"), .skipped)
        XCTAssertNil(OwnerKeyVerification(rawValue: "trusted"))
    }

    // MARK: Backfill rule (shares pinned before decisions were recorded)

    func testBackfillGrandfathersPinnedZoneWithoutMarker() {
        // Pinned and in active use → marked as taken delivery of, once. Not
        // `confirmed`: nobody compared a code.
        XCTAssertEqual(OwnerKeyVerification.backfillState(hasPin: true, existing: nil),
                       .accepted)
    }

    func testBackfillLeavesUnpinnedZoneUnmarked() {
        // No pin yet → no marker; the normal path applies when the pin lands.
        // Marking here would default-trust a share the user has never seen.
        XCTAssertNil(OwnerKeyVerification.backfillState(hasPin: false, existing: nil))
    }

    func testBackfillNeverOverwritesAnExistingMarker() {
        // Idempotence across re-runs (reinstall keeps Keychain markers but
        // resets the one-shot flag): whatever was recorded stays recorded.
        for existing in [OwnerKeyVerification.pending, .accepted, .skipped, .confirmed] {
            XCTAssertEqual(OwnerKeyVerification.backfillState(hasPin: true, existing: existing),
                           existing)
        }
    }
}
