import XCTest
@testable import Vaultify

/// Truth table for the owner-side "they accepted" banner decision: it fires
/// only on the lifecycle crossing INTO ready-for-ceremony while the app is
/// not frontmost. Pure logic — no UNUserNotificationCenter, no CloudKit.
@MainActor
final class ShareStatusNotifierTests: XCTestCase {

    func testFiresOnCrossingIntoReadyWhileInactive() {
        XCTAssertTrue(ShareStatusNotifier.shouldNotify(previous: .inviteSent,
                                                       next: .readyForCeremony,
                                                       appActive: false))
        XCTAssertTrue(ShareStatusNotifier.shouldNotify(previous: .accepted,
                                                       next: .readyForCeremony,
                                                       appActive: false))
    }

    func testNeverFiresWhileAppIsActive() {
        // Foreground: the pending row on Home updates instead of a banner.
        XCTAssertFalse(ShareStatusNotifier.shouldNotify(previous: .accepted,
                                                        next: .readyForCeremony,
                                                        appActive: true))
    }

    func testNeverFiresOnReResolveOfAnAlreadyReadyShare() {
        // Same state re-observed (push retry, foreground refresh) must not
        // re-bang the banner — only the crossing counts.
        XCTAssertFalse(ShareStatusNotifier.shouldNotify(previous: .readyForCeremony,
                                                        next: .readyForCeremony,
                                                        appActive: false))
    }

    func testNeverFiresOnOtherMilestones() {
        // Acceptance alone is deliberately silent (one acceptance would
        // otherwise produce two banners minutes apart)...
        XCTAssertFalse(ShareStatusNotifier.shouldNotify(previous: .inviteSent,
                                                        next: .accepted,
                                                        appActive: false))
        // ...and completing the ceremony needs no banner: the owner did it.
        XCTAssertFalse(ShareStatusNotifier.shouldNotify(previous: .readyForCeremony,
                                                        next: .active,
                                                        appActive: false))
    }

    func testNeverFiresOnARegression() {
        // The store is monotonic so this cannot happen through it, but the
        // decision itself must not rely on that.
        XCTAssertFalse(ShareStatusNotifier.shouldNotify(previous: .active,
                                                        next: .readyForCeremony,
                                                        appActive: false))
    }
}
