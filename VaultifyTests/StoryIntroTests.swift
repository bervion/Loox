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

    /// The swarm is the chaos beat's whole message, and nothing else in the
    /// suite would notice if it stopped being drawn: a break in birth or
    /// scatter that left every scrap invisible, or collapsed on the origin,
    /// would otherwise pass.
    func testChaosBeatShowsAScatteredSwarm() {
        let samples = (0..<StoryField.scrapCount)
            .map { StoryField.sample(index: $0, t: 8, beat: 1) }
            .filter { $0.opacity > 0 }
        XCTAssertGreaterThan(samples.count, StoryField.scrapCount / 2,
                             "the chaos page must rest on a fully born swarm")
        let xs = samples.map(\.position.x), ys = samples.map(\.position.y)
        let spread = max((xs.max() ?? 0) - (xs.min() ?? 0),
                         (ys.max() ?? 0) - (ys.min() ?? 0))
        XCTAssertGreaterThan(spread, 0.3, "scraps must be scattered, not stacked on the origin")
    }

    /// Every stage window must be COMPLETE on the integer its page rests at —
    /// the defect class that left the consequence chip missing (the copy told
    /// the user to tap something that was not drawn yet) and the sanctuary
    /// half-built while the user looked straight at it.
    func testConsequenceAndSanctuaryAreComposedAtRest() {
        // Drift has stopped by the consequence page: sampling twice at
        // different times must give the same position.
        for index in [0, 11, 47] {
            let a = StoryField.sample(index: index, t: 3, beat: 2)
            let b = StoryField.sample(index: index, t: 9, beat: 2)
            XCTAssertEqual(a.position.x, b.position.x, accuracy: 0.001)
            XCTAssertEqual(a.position.y, b.position.y, accuracy: 0.001)
        }
        // The ring is closed by the turn page, so the sanctuary opens on it.
        for index in 0..<StoryField.ringCount {
            let sample = StoryField.sample(index: index, t: 5, beat: 3)
            let dx = sample.position.x - StoryField.origin.x
            let dy = sample.position.y - StoryField.origin.y
            XCTAssertEqual((dx * dx + dy * dy).squareRoot(), 0.24, accuracy: 0.06)
        }
    }

    // MARK: Completion-flag semantics

    @MainActor
    func testStoryFlagDefaultsSeenForUpgradingInstalls() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "onboarding_completed")
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        XCTAssertTrue(settings.storyIntroCompleted,
                      "an already-onboarded install must not replay the story after updating")
    }

    @MainActor
    func testStoryFlagDefaultsUnseenForFreshInstalls() throws {
        // A suite-scoped UserDefaults still searches the app's OWN domain, so a
        // value left by a normal DEBUG launch would read straight through and
        // make this pass or fail by accident. Clear both keys for the duration.
        let standard = UserDefaults.standard
        let keys = ["story_intro_completed", "story_intro_wants_first_item"]
        let saved = keys.map { standard.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { standard.set(value, forKey: key) } else { standard.removeObject(forKey: key) }
            }
        }
        keys.forEach { standard.removeObject(forKey: $0) }

        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        XCTAssertFalse(settings.storyIntroCompleted)
        XCTAssertFalse(settings.storyIntroWantsFirstItem)
    }

    /// The resolved default must be WRITTEN, not recomputed every launch: the
    /// fallback keys off `onboardingCompleted`, which onboarding has just set,
    /// so a story the user was interrupted in would otherwise read as seen
    /// forever instead of replaying.
    @MainActor
    func testFreshInstallPinsTheStoryFlagSoAnInterruptedStoryReplays() throws {
        let standard = UserDefaults.standard
        let key = "story_intro_completed"
        let saved = standard.object(forKey: key)
        defer {
            if let saved { standard.set(saved, forKey: key) } else { standard.removeObject(forKey: key) }
        }
        standard.removeObject(forKey: key)

        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        XCTAssertEqual(defaults.object(forKey: key) as? Bool, false,
                       "a fresh install must persist false, not re-derive it after onboarding")

        // Onboarding completes, the story is abandoned, the app relaunches.
        defaults.set(true, forKey: "onboarding_completed")
        let relaunched = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        XCTAssertFalse(relaunched.storyIntroCompleted, "the story must still be owed")
    }

    // MARK: Helpers

    private func freshDefaults() throws -> (UserDefaults, String) {
        let suite = "com.bervion.vaultify.story-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
