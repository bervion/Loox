import XCTest
@testable import Vaultify

/// Story intro invariants: deterministic stage math, one-shot interaction
/// events, and the completion-flag semantics that keep the story from ever
/// showing twice (or surprising an upgrading user).
final class StoryIntroTests: XCTestCase {

    // MARK: StoryField (pure math)

    func testFieldIsDeterministic() {
        for index in [0, 7, 42, StoryField.scrapCount - 1] {
            let a = StoryField.sample(index: index, t: 12.34, beat: 2.6)
            let b = StoryField.sample(index: index, t: 12.34, beat: 2.6)
            XCTAssertEqual(a.position, b.position)
            XCTAssertEqual(a.opacity, b.opacity)
            XCTAssertEqual(a.scale, b.scale)
        }
    }

    func testScrapsUnbornAtHook() {
        for index in 0..<StoryField.scrapCount {
            XCTAssertEqual(StoryField.sample(index: index, t: 5, beat: 0).opacity, 0,
                           "the hook opens on the lone dot, before any scrap is born")
        }
    }

    func testSurvivorsOrbitAndSurplusDissolvesInSanctuary() {
        for index in 0..<StoryField.scrapCount {
            let sample = StoryField.sample(index: index, t: 30, beat: 4.4)
            if index < StoryField.ringCount {
                XCTAssertGreaterThan(sample.opacity, 0.9)
                let dx = sample.position.x - StoryField.origin.x
                let dy = sample.position.y - StoryField.origin.y
                let distance = (dx * dx + dy * dy).squareRoot()
                XCTAssertEqual(distance, 0.24, accuracy: 0.06,
                               "survivors should sit on the sanctuary orbit")
            } else {
                XCTAssertEqual(sample.opacity, 0, accuracy: 0.001,
                               "surplus scraps dissolve as the ring settles")
            }
        }
    }

    func testSealBurstExtinguishesTheRing() {
        let sample = StoryField.sample(index: 3, t: 40, beat: 5, burst: 1)
        XCTAssertEqual(sample.opacity, 0, accuracy: 0.001)
    }

    // MARK: Scroll model

    @MainActor
    func testProgressClampsAndMapsToBeats() {
        let model = StoryScrollProgressModel()
        model.update(StoryScrollMetrics(offset: -50, span: 1000))
        XCTAssertEqual(model.journeyProgress, 0)
        model.update(StoryScrollMetrics(offset: 500, span: 1000))
        XCTAssertEqual(model.journeyProgress, 0.5, accuracy: 0.01)
        XCTAssertEqual(model.beatPosition, 2.5, accuracy: 0.05)
        model.update(StoryScrollMetrics(offset: 2000, span: 1000))
        XCTAssertEqual(model.journeyProgress, 1)
        model.update(StoryScrollMetrics(offset: 100, span: 0))
        XCTAssertEqual(model.journeyProgress, 1, "a degenerate span must be ignored")
    }

    @MainActor
    func testSendTapAndSealAreOneShot() {
        let model = StoryScrollProgressModel()
        XCTAssertNil(model.sendTapTime)
        model.noteSendTap()
        let firstTap = model.sendTapTime
        XCTAssertNotNil(firstTap)
        model.noteSendTap()
        XCTAssertEqual(model.sendTapTime, firstTap, "sent is sent — no re-arming")

        XCTAssertNil(model.sealTime)
        model.noteSeal()
        let firstSeal = model.sealTime
        XCTAssertNotNil(firstSeal)
        model.noteSeal()
        XCTAssertEqual(model.sealTime, firstSeal)
    }

    // MARK: Completion-flag semantics

    @MainActor
    func testStoryFlagDefaultsSeenForUpgradingInstalls() {
        let suite = "story-tests-upgrade"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "onboarding_completed")
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        XCTAssertTrue(settings.storyIntroCompleted,
                      "an already-onboarded install must not replay the story after updating")
        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    func testStoryFlagDefaultsUnseenForFreshInstalls() {
        let suite = "story-tests-fresh"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        XCTAssertFalse(settings.storyIntroCompleted)
        XCTAssertFalse(settings.storyIntroWantsFirstItem)
        defaults.removePersistentDomain(forName: suite)
    }
}
