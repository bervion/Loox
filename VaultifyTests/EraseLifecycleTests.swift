import XCTest
@testable import Vaultify

/// Erase Vault had zero automated coverage while doing the most destructive
/// thing in the app. These pin the parts that are not recoverable if they are
/// wrong: what the user is told happened, what is retained so a live quick link
/// stays killable, and what is actually removed from disk.
@MainActor
final class EraseLifecycleTests: XCTestCase {

    // MARK: Per-step outcome

    func testCleanReportHasNoFailuresAndNothingToRetry() {
        var report = EraseTeardownReport()
        for step in EraseStep.allCases { report.record(.nothingToDo(step)) }
        XCTAssertTrue(report.isClean)
        XCTAssertTrue(report.failedSteps.isEmpty)
        XCTAssertTrue(report.failureLines.isEmpty)
    }

    func testFailedStepsAreTheOnlyOnesARetryReRuns() {
        var report = EraseTeardownReport()
        report.record(EraseStepOutcome(step: .quickLinks, attempted: 3, failed: 2))
        report.record(.single(.cloudVault, succeeded: false))
        report.record(.single(.inviteInbox, succeeded: true))
        report.record(.nothingToDo(.emailAliases))

        XCTAssertFalse(report.isClean)
        XCTAssertEqual(report.failedSteps, [.quickLinks, .cloudVault])
    }

    func testRetryOutcomeReplacesTheEarlierOneForTheSameStep() {
        var report = EraseTeardownReport()
        report.record(EraseStepOutcome(step: .quickLinks, attempted: 3, failed: 3))
        report.record(EraseStepOutcome(step: .quickLinks, attempted: 3, failed: 1))

        XCTAssertEqual(report.failures.count, 1, "A retry must not append a second line for one step")
        XCTAssertEqual(report.failures.first?.failed, 1)
    }

    func testOutcomesStayInTeardownOrderRegardlessOfWhenTheyLanded() {
        var report = EraseTeardownReport()
        report.record(.single(.cloudVault, succeeded: false))
        report.record(EraseStepOutcome(step: .quickLinks, attempted: 1, failed: 1))
        XCTAssertEqual(report.failedSteps, [.quickLinks, .cloudVault])
    }

    func testQuickLinksAreTornDownBeforeAnythingElse() {
        // Not cosmetic: the revoke token is destroyed by the local wipe, and a
        // link outlives the vault by up to its expiry.
        XCTAssertEqual(EraseStep.allCases.first, .quickLinks)
    }

    // MARK: What the user is told

    func testFailureMessageNamesEveryLiveSurface() {
        var report = EraseTeardownReport()
        report.record(EraseStepOutcome(step: .quickLinks, attempted: 2, failed: 2))
        report.record(.single(.emailAliases, succeeded: false))
        report.record(.single(.cloudVault, succeeded: true))

        XCTAssertEqual(report.failureLines.count, 2)
        let message = report.failureMessage
        XCTAssertTrue(message.contains(report.failureLines[0]))
        XCTAssertTrue(message.contains(report.failureLines[1]))
    }

    func testQuickLinkCountReachesTheUser() {
        var report = EraseTeardownReport()
        report.record(EraseStepOutcome(step: .quickLinks, attempted: 5, failed: 3))
        // How many links are still readable is the number that decides whether
        // "Erase Anyway" is acceptable, so it must survive into the copy.
        XCTAssertTrue(report.failureMessage.contains("3"))
    }

    func testRetainedKeyPromiseAppearsOnlyWhenQuickLinksFailed() {
        var linksFailed = EraseTeardownReport()
        linksFailed.record(EraseStepOutcome(step: .quickLinks, attempted: 1, failed: 1))
        let promise = appString("The keys needed to turn those links off are kept on this device.")
        XCTAssertTrue(linksFailed.failureMessage.contains(promise))

        var linksFine = EraseTeardownReport()
        linksFine.record(.single(.cloudVault, succeeded: false))
        XCTAssertFalse(linksFine.failureMessage.contains(promise))
    }

    // MARK: Quick-link revoke, offline

    /// The failure the whole M8 fix exists for: no network, so nothing can be
    /// revoked, and every token has to survive to stay killable later.
    func testOfflineRevokeReportsEveryLinkAndKeepsItsToken() async {
        installUnroutableLinkAPI()
        defer { restoreLinkAPI() }
        let service = LooxLinkService(persistenceEnabled: false)
        service.records.add(makeRecord(shareId: "a"))
        service.records.add(makeRecord(shareId: "b"))

        let result = await service.revokeAllForErase()

        XCTAssertEqual(result.attempted, 2)
        XCTAssertEqual(result.failed.map(\.shareId).sorted(), ["a", "b"])
        XCTAssertEqual(service.records.records.count, 2,
                       "A revoke that never landed must not drop the record that carries the token")
    }

    func testExpiredLinksAreNeverAttempted() async {
        installUnroutableLinkAPI()
        defer { restoreLinkAPI() }
        let service = LooxLinkService(persistenceEnabled: false)
        service.records.add(makeRecord(shareId: "live"))
        service.records.add(makeRecord(shareId: "dead", expiresIn: -60))

        let result = await service.revokeAllForErase()

        // Expired links are already 404 server-side; attempting them would only
        // slow an erase down and inflate the "still live" count.
        XCTAssertEqual(result.attempted, 1)
        XCTAssertEqual(result.failed.map(\.shareId), ["live"])
    }

    func testNothingToRevokeIsNotAFailure() async {
        let service = LooxLinkService(persistenceEnabled: false)
        let result = await service.revokeAllForErase()
        XCTAssertEqual(result.attempted, 0)
        XCTAssertTrue(result.failed.isEmpty)
    }

    // MARK: Retention

    func testWipeKeepsOnlyTheRecordsThatCouldNotBeRevoked() {
        let store = LooxLinkRecordStore(persistenceEnabled: false)
        let stillLive = makeRecord(shareId: "still-live")
        store.add(makeRecord(shareId: "revoked"))
        store.add(stillLive)

        store.wipe(keeping: [stillLive])

        XCTAssertEqual(store.records.map(\.shareId), ["still-live"])
        XCTAssertEqual(store.records.first?.revokeToken, stillLive.revokeToken)
    }

    func testWipeWithNothingRetainedEmptiesTheRegistry() {
        let store = LooxLinkRecordStore(persistenceEnabled: false)
        store.add(makeRecord(shareId: "a"))
        store.wipe()
        XCTAssertTrue(store.records.isEmpty)
    }

    // MARK: Environment-level erase

    func testEraseKeepsTheTokensOfLinksThatAreStillLive() {
        let env = AppEnvironment(uiTestConfiguration: .disabled)
        let stillLive = makeRecord(shareId: "unrevoked")
        env.looxLinks.records.add(makeRecord(shareId: "revoked"))
        env.looxLinks.records.add(stillLive)

        env.finishErase(retainingLinks: [stillLive])

        XCTAssertEqual(env.looxLinks.records.records.map(\.shareId), ["unrevoked"])
    }

    func testEraseOnThisDeviceKeepsEveryLiveLinkKillable() {
        let env = AppEnvironment(uiTestConfiguration: .disabled)
        env.looxLinks.records.add(makeRecord(shareId: "a"))
        env.looxLinks.records.add(makeRecord(shareId: "expired", expiresIn: -60))

        // Nothing remote was torn down, so this device's tokens are still the
        // only way to kill the links it created.
        env.eraseThisDevice()

        XCTAssertEqual(env.looxLinks.records.records.map(\.shareId), ["a"])
    }

    func testEraseClearsFaviconAndAttachmentResidue() throws {
        let env = AppEnvironment(uiTestConfiguration: .disabled)
        let root = try XCTUnwrap(env.isolatedFileRoot)
        let attachments = root.appending(path: "Attachments")
        let favicons = root.appending(path: "Favicons")
        try Data("sealed".utf8).write(to: attachments.appending(path: "\(UUID().uuidString).enc"))
        try Data("icon".utf8).write(to: favicons.appending(path: "example.com.img"))

        env.eraseThisDevice()

        // A favicon filename is a plaintext record of a site the user had a
        // login for; an attachment blob's size and timestamp are a record that
        // the vault existed. Both used to survive an erase.
        XCTAssertTrue(contents(of: attachments).isEmpty)
        XCTAssertTrue(contents(of: favicons).isEmpty)
    }

    func testTeardownUnderTestIsolationTouchesNoRemoteServiceAndStillReports() async {
        let env = AppEnvironment(uiTestConfiguration: .disabled)
        let report = await env.tearDownRemoteState(steps: EraseStep.allCases)
        // Every requested step is accounted for even when nothing ran, so the
        // flow can never treat a missing outcome as a silent success.
        XCTAssertEqual(report.outcomes.map(\.step), EraseStep.allCases)
        XCTAssertTrue(report.isClean)
    }

    // MARK: Tutorial isolation

    func testIsolatedLaunchAnswersEveryTutorialFlow() throws {
        _ = AppEnvironment(uiTestConfiguration: .disabled)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UITestConfiguration.settingsDefaultsSuite))
        let store = TutorialStore(defaults: defaults)
        for flowID in TutorialFlow.allFlowIDs {
            // A tour draws a full-screen scrim, and everything under a scrim is
            // non-hittable — that is what was failing the UI tests.
            XCTAssertFalse(store.shouldPresent(flowID), "\(flowID) would still present a tour")
        }
    }

    func testATestCanOptBackIntoTheTutorials() throws {
        // Deliberately does NOT write UserDefaults.standard. Doing so wrote into
        // the app host's real defaults, and when the host died before cleanup the
        // flag survived on the simulator and broke every later launch. The opt-in
        // is a launch argument precisely so it cannot outlive the process.
        XCTAssertTrue(
            AppEnvironment.tutorialLaunchArgument.hasPrefix("-"),
            "the opt-in must be a launch argument, not a defaults key")

        _ = AppEnvironment(uiTestConfiguration: .disabled)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UITestConfiguration.settingsDefaultsSuite))
        let store = TutorialStore(defaults: defaults)
        XCTAssertTrue(store.shouldPresent(TutorialFlow.firstRun.id))
    }

    // MARK: Helpers

    private func makeRecord(shareId: String, expiresIn: TimeInterval = 3_600) -> LooxLinkRecord {
        LooxLinkRecord(shareId: shareId, revokeToken: "token-\(shareId)", itemId: "item-\(shareId)",
                       createdAt: .now, expiresAt: .now.addingTimeInterval(expiresIn))
    }

    private func contents(of directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    }

    /// Points the link client at a closed local port so a revoke fails the way
    /// it fails with no network, through the real request path.
    private static let apiBaseKey = "loox_link_api_base_url"
    private var savedAPIBase: String?

    private func installUnroutableLinkAPI() {
        savedAPIBase = UserDefaults.standard.string(forKey: Self.apiBaseKey)
        UserDefaults.standard.set("http://127.0.0.1:9", forKey: Self.apiBaseKey)
    }

    private func restoreLinkAPI() {
        if let savedAPIBase {
            UserDefaults.standard.set(savedAPIBase, forKey: Self.apiBaseKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.apiBaseKey)
        }
        savedAPIBase = nil
    }
}
