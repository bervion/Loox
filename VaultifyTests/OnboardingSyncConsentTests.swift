import XCTest
@testable import Vaultify

/// Onboarding used to turn iCloud sync on unconditionally right after `createVault`, so
/// the first CloudKit write landed on the name step's three-second mutation debounce —
/// before the user had seen anything resembling a choice. These pin the replacement: no
/// egress without an explicit yes, and no cross-device recovery claim without a confirmed
/// envelope upload behind it.
@MainActor
final class OnboardingSyncConsentTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "onboarding.consent.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// Records what the controller was allowed to do, so "no CloudKit write occurred" is
    /// an assertion about a call count rather than a hope about a network layer.
    private final class SyncSpy {
        private(set) var applied: [Bool] = []
        private(set) var pushCount = 0
        var pushError: Error?

        func apply(_ isOn: Bool) { applied.append(isOn) }

        func push() async throws {
            pushCount += 1
            if let pushError { throw pushError }
        }
    }

    private struct UploadRefused: LocalizedError {
        var errorDescription: String? { "iCloud refused the upload" }
    }

    // MARK: Consent gate

    func testFreshInstallHasSyncOff() {
        // The whole contract rests on this default; onboarding overriding it is the bug
        // being fixed, and nothing pinned the default itself.
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        XCTAssertFalse(settings.iCloudSyncEnabled)
    }

    func testReachingTheKitStepWithoutAnsweringLeavesSyncOffAndUploadsNothing() async {
        // Stands in for the whole create → name → Emergency Kit run with the sync
        // question never answered: nothing writes the flag, nothing pushes.
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        let spy = SyncSpy()
        let controller = SyncConsentController()

        // Everything the screen can do without a tap on one of the two options.
        await controller.retry(push: spy.push)

        XCTAssertEqual(controller.consent, .notAnswered)
        XCTAssertFalse(controller.consent.allowsCloudEgress)
        XCTAssertFalse(settings.iCloudSyncEnabled)
        XCTAssertEqual(spy.pushCount, 0)
        XCTAssertTrue(spy.applied.isEmpty)
    }

    func testNothingIsPreselected() {
        let controller = SyncConsentController()
        XCTAssertEqual(controller.consent, .notAnswered)
        XCTAssertEqual(controller.upload, .notStarted)
        XCTAssertNil(controller.uploadFailure)
    }

    func testOnlyAnExplicitYesAllowsEgress() {
        XCTAssertFalse(SyncConsent.notAnswered.allowsCloudEgress)
        XCTAssertFalse(SyncConsent.declined.allowsCloudEgress)
        XCTAssertTrue(SyncConsent.granted.allowsCloudEgress)
    }

    func testDecliningWritesTheFlagOffAndNeverUploads() {
        let spy = SyncSpy()
        let controller = SyncConsentController()

        controller.decline(apply: spy.apply)

        XCTAssertEqual(controller.consent, .declined)
        XCTAssertEqual(spy.applied, [false])
        XCTAssertEqual(spy.pushCount, 0)
    }

    func testRetryAfterDecliningUploadsNothing() async {
        // A stale retry must not resurrect egress the user turned back off.
        let spy = SyncSpy()
        let controller = SyncConsentController()
        controller.decline(apply: spy.apply)

        await controller.retry(push: spy.push)

        XCTAssertEqual(spy.pushCount, 0)
    }

    // MARK: Awaited upload

    func testGrantingSyncTurnsTheFlagOnAndAwaitsExactlyOneUpload() async {
        let spy = SyncSpy()
        let controller = SyncConsentController()

        await controller.grant(apply: spy.apply, push: spy.push)

        XCTAssertEqual(spy.applied, [true])
        XCTAssertEqual(spy.pushCount, 1)
        XCTAssertEqual(controller.upload, .uploaded)
    }

    func testAFailedUploadIsReportedInsteadOfSwallowed() async {
        let spy = SyncSpy()
        spy.pushError = UploadRefused()
        let controller = SyncConsentController()

        await controller.grant(apply: spy.apply, push: spy.push)

        XCTAssertEqual(controller.upload, .failed("iCloud refused the upload"))
        XCTAssertEqual(controller.uploadFailure, "iCloud refused the upload")
    }

    func testRetryAfterAFailureCanStillSucceed() async {
        let spy = SyncSpy()
        spy.pushError = UploadRefused()
        let controller = SyncConsentController()
        await controller.grant(apply: spy.apply, push: spy.push)

        spy.pushError = nil
        await controller.retry(push: spy.push)

        XCTAssertEqual(spy.pushCount, 2)
        XCTAssertEqual(controller.upload, .uploaded)
        // Consent was granted once; a retry must not re-write the settings flag.
        XCTAssertEqual(spy.applied, [true])
    }

    // MARK: What the printed kit may claim

    func testKitScopeIsCrossDeviceOnlyAfterAConfirmedUpload() {
        XCTAssertEqual(EmergencyKitScope.resolve(consent: .granted, upload: .uploaded), .crossDevice)
    }

    func testSyncOnButNotYetUploadedStillOnlyPromisesAPasswordReset() {
        // The exact case the old silent best-effort push hid: the toggle says on, the
        // envelope is not there, and a new device has nothing to restore from.
        for upload in [RecoveryEnvelopeUpload.notStarted, .uploading, .failed("offline")] {
            XCTAssertEqual(EmergencyKitScope.resolve(consent: .granted, upload: upload),
                           .thisInstallationOnly,
                           "sync on with upload \(upload) must not promise cross-device recovery")
        }
    }

    func testNoConsentNeverPromisesCrossDeviceRecovery() {
        for consent in [SyncConsent.notAnswered, .declined] {
            XCTAssertEqual(EmergencyKitScope.resolve(consent: consent, upload: .uploaded),
                           .thisInstallationOnly)
        }
    }

    func testAKitDefaultsToTheNarrowerClaim() {
        // A caller that forgets to resolve the scope must under-promise, never over-promise.
        let info = EmergencyKitInfo(recoveryKey: "AAAA-BBBB-CCCC-DDDD", ownerName: "",
                                    iCloudAccount: "", createdAt: .now)
        XCTAssertEqual(info.scope, .thisInstallationOnly)
    }

    func testControllerScopeFollowsTheAwaitedUpload() async {
        let spy = SyncSpy()
        let controller = SyncConsentController()
        XCTAssertEqual(controller.scope, .thisInstallationOnly)

        await controller.grant(apply: spy.apply, push: spy.push)
        XCTAssertEqual(controller.scope, .crossDevice)

        controller.decline(apply: spy.apply)
        XCTAssertEqual(controller.scope, .thisInstallationOnly)
    }

    // MARK: The regression itself

    func testOnboardingFlowNeverEnablesSyncOrStartsASync() throws {
        // Source-level because the offending line was a single unconditional assignment
        // with a confident, factually wrong comment above it — exactly the shape that
        // survives review and that no runtime assertion in this suite could reach.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let flow = try String(
            contentsOf: root.appendingPathComponent("Vaultify/Features/Onboarding/OnboardingFlow.swift"),
            encoding: .utf8)

        XCTAssertFalse(flow.contains("iCloudSyncEnabled ="),
                       "OnboardingFlow must not write the sync flag: consent lives on the Emergency Kit step")
        XCTAssertFalse(flow.contains("syncNow()"),
                       "OnboardingFlow must not kick a sync: the envelope push is awaited by the consent step")
    }
}
