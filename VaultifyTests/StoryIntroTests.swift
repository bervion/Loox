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
        let beat = 4.4
        for index in 0..<StoryField.scrapCount {
            let sample = StoryField.sample(index: index, t: 30, beat: beat)
            if index < StoryField.ringCount {
                XCTAssertGreaterThan(sample.opacity, 0.9)
                XCTAssertEqual(orbitRadius(of: sample), expectedRadius(slot: index, beat: beat),
                               accuracy: 0.002,
                               "survivors should sit on their lattice orbit")
                XCTAssertEqual(sample.bubbleMix, 1, accuracy: 0.001,
                               "a gathered scrap is a brand bubble, not a card")
            } else {
                XCTAssertEqual(sample.opacity, 0, accuracy: 0.001,
                               "surplus scraps dissolve as the cluster settles")
            }
        }
    }

    /// The defect the user saw: 90 cards converging on 24 slots left three
    /// stacked per slot on the turn page, and the cards themselves were wider
    /// than the arc between slots. The cluster must close on exactly one bubble
    /// per slot, with daylight between neighbours on EVERY orbit.
    func testGatheredBubblesNeverOverlap() {
        for size in Self.canvases {
            let reach = StoryOrbitLattice.reach(size)
            let ringScale = CGSize(
                width: reach / (StoryField.ringRadius * size.width),
                height: reach / (StoryField.ringRadius * size.height))

            var discs: [(center: CGPoint, radius: CGFloat)] = []
            for index in 0..<StoryField.scrapCount {
                let sample = StoryField.sample(index: index, t: 30, beat: 4.4,
                                               ringScale: ringScale, reach: reach)
                guard sample.opacity > 0.01 else { continue }
                discs.append((CGPoint(x: sample.position.x * size.width,
                                      y: sample.position.y * size.height),
                              StoryOrbitLattice.bubbleBase * sample.bubbleScale / 2))
            }
            XCTAssertEqual(discs.count, StoryField.ringCount,
                           "one bubble per slot on \(size) — nothing stacked, nothing spare")

            for i in discs.indices {
                for j in discs.indices where j > i {
                    let dx = discs[i].center.x - discs[j].center.x
                    let dy = discs[i].center.y - discs[j].center.y
                    XCTAssertGreaterThan((dx * dx + dy * dy).squareRoot(),
                                         discs[i].radius + discs[j].radius,
                                         "bubbles \(i) and \(j) overlap on \(size)")
                }
            }
        }
    }

    /// The lattice's clearances are DIMENSIONLESS — every length in it is a
    /// fraction of `reach` — so proving them once proves them on every canvas
    /// and through the commitment beat's contraction. This is the guard that
    /// makes a future retune of ring counts or bubble sizes safe.
    func testLatticeClearancesAreScaleFree() {
        XCTAssertGreaterThan(StoryOrbitLattice.minimumNeighbourGap, 0.05,
                             "bubbles on one orbit must not touch")
        XCTAssertGreaterThan(StoryOrbitLattice.minimumShellGap, 0.05,
                             "mark, the three orbits and the sigils must not touch")
    }

    /// The art and the copy column take their bound from ONE constant. Two
    /// independent numbers is how the sigils ended up sweeping through the
    /// sanctuary title on a small phone.
    func testArtNeverGrowsPastTheCopyFloor() {
        for size in Self.canvases {
            let reach = StoryOrbitLattice.reach(size)
            let ringScale = CGSize(
                width: reach / (StoryField.ringRadius * size.width),
                height: reach / (StoryField.ringRadius * size.height))
            let sigil = Double(reach) * (StoryOrbitLattice.sigilRadii.max() ?? 0)
            var lowest = StoryField.origin.y + sigil / Double(size.height)

            // The ambient motes are art too, and they drift: a mote floating
            // behind the sanctuary title is solid brand colour, not a 2pt arc.
            for index in 0..<StoryOrbitLattice.ambientCount {
                guard let mote = StoryOrbitLattice.mote(index: index, t: 21, beat: 4,
                                                        burst: 0, scale: ringScale,
                                                        reach: reach) else { continue }
                let half = Double(StoryOrbitLattice.bubbleBase) * mote.scale / 2
                lowest = max(lowest, mote.position.y + half / Double(size.height))
            }
            XCTAssertLessThanOrEqual(lowest, StoryOrbitLattice.artFloor + 0.001,
                                     "the cluster reaches past the copy floor on \(size)")
        }
    }

    /// Smallest supported phone through to the biggest iPad, in both
    /// orientations where it matters.
    private static let canvases = [
        CGSize(width: 375, height: 667),    // iPhone SE 3
        CGSize(width: 393, height: 852),    // iPhone 16
        CGSize(width: 440, height: 956),    // iPhone 16 Pro Max
        CGSize(width: 834, height: 1194),   // iPad 11 portrait
        CGSize(width: 1194, height: 834),   // iPad 11 landscape
    ]

    /// The surplus has to be gone BEFORE the cluster closes, not after: the old
    /// field kept it fully lit until beat 3.3, which is what the user was
    /// looking straight at on the turn page.
    func testSurplusIsAbsorbedBeforeTheClusterCloses() {
        for index in StoryField.ringCount..<StoryField.scrapCount {
            XCTAssertEqual(StoryField.sample(index: index, t: 12, beat: 3).opacity, 0,
                           accuracy: 0.001,
                           "the turn page must rest on the cluster alone")
        }
    }

    private func orbitRadius(of sample: StoryField.Sample) -> Double {
        let dx = sample.position.x - StoryField.origin.x
        let dy = sample.position.y - StoryField.origin.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func expectedRadius(slot: Int, beat: Double) -> Double {
        StoryField.ringRadius
            * StoryOrbitLattice.placement(slot: slot).ring.radius
            * StoryOrbitLattice.tighten(beat)
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
    func testCoarseBeatPublishesPerQuantumAndAtEndStops() {
        let model = StoryScrollProgressModel()
        let quantum = StoryScrollProgressModel.coarseQuantum
        // A sub-quantum wiggle updates the live beat but not the coarse mirror
        // (the whole point: scroll churn must not invalidate observers).
        model.update(StoryScrollMetrics(offset: 2, span: 1000))
        XCTAssertGreaterThan(model.beatPosition, 0)
        XCTAssertLessThan(model.beatPosition, quantum)
        XCTAssertEqual(model.coarseBeat, 0, "sub-quantum moves must not publish")
        // Crossing the quantum publishes, and tracks within one step after.
        model.update(StoryScrollMetrics(offset: 200, span: 1000))
        XCTAssertEqual(model.coarseBeat, model.beatPosition, accuracy: quantum)
        // The end stops always land exactly, whatever the quantum phase.
        model.update(StoryScrollMetrics(offset: 1000, span: 1000))
        XCTAssertEqual(model.coarseBeat, 5)
        model.update(StoryScrollMetrics(offset: 0, span: 1000))
        XCTAssertEqual(model.coarseBeat, 0)
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
        // The cluster is closed by the turn page, so the sanctuary opens on it.
        for index in 0..<StoryField.ringCount {
            let sample = StoryField.sample(index: index, t: 5, beat: 3)
            XCTAssertEqual(orbitRadius(of: sample), expectedRadius(slot: index, beat: 3),
                           accuracy: 0.002)
        }
    }

    // MARK: Haptic score

    /// Silence everywhere except the turn. The DNA vocabulary gives scrolling
    /// and navigation no haptic, so the ratchet must exist ONLY across the beat
    /// where the finger is manipulating the swarm rather than turning a page.
    func testOnlyTheTurnCarriesAHapticTexture() {
        let window = StoryField.gatherWindow
        for beat in stride(from: 0.0, through: 5.0, by: 0.01) {
            let detent = StoryScrollProgressModel.gatherDetent(at: beat)
            if beat > window.start, beat < window.end {
                XCTAssertNotNil(detent, "the turn must be detented at beat \(beat)")
            } else {
                XCTAssertNil(detent, "beat \(beat) is navigation — it must be silent")
            }
        }
    }

    /// The ratchet spans the window evenly and stays in range, so the texture
    /// cannot bunch at one end or overrun the detent count.
    func testGatherDetentsAreMonotonicAndBounded() {
        let window = StoryField.gatherWindow
        var previous = -1
        var seen = Set<Int>()
        for step in 1..<1000 {
            let beat = window.start + (window.end - window.start) * Double(step) / 1000
            guard let detent = StoryScrollProgressModel.gatherDetent(at: beat) else { continue }
            XCTAssertGreaterThanOrEqual(detent, previous, "the ratchet must not run backwards")
            XCTAssertLessThan(detent, StoryScrollProgressModel.gatherDetents)
            previous = detent
            seen.insert(detent)
        }
        XCTAssertEqual(seen.count, StoryScrollProgressModel.gatherDetents,
                       "every detent must be reachable across the turn")
    }

    /// Dragging back visibly scatters the swarm again, so the texture has to
    /// answer in reverse too — every adjacent pair of detents must be distinct
    /// in both directions.
    ///
    /// Sampled at each detent's CENTRE, never at its edge: the boundaries fall
    /// on exact multiples where a single ULP decides which side a beat lands
    /// on, so an edge sample tests floating-point luck rather than the ratchet.
    func testGatherRatchetTicksInBothDirections() {
        let window = StoryField.gatherWindow
        let span = window.end - window.start
        let count = StoryScrollProgressModel.gatherDetents
        let centres = (0..<count).map { index in
            window.start + span * (Double(index) + 0.5) / Double(count)
        }
        let indices = centres.map { StoryScrollProgressModel.gatherDetent(at: $0) }
        XCTAssertEqual(indices, (0..<count).map { $0 },
                       "each detent's centre must report that detent")
        for (down, up) in zip(indices, indices.dropFirst()) {
            XCTAssertNotEqual(down, up, "the ratchet must tick in both directions")
        }
    }

    /// Standing still must be silent. `update` returns before scoring when the
    /// progress has not moved, so parking the finger on a detent boundary
    /// cannot buzz repeatedly.
    @MainActor
    func testAStationaryFingerNeverTicks() {
        let model = StoryScrollProgressModel()
        let metrics = StoryScrollMetrics(offset: 500, span: 1000)
        model.update(metrics)
        let settled = model.journeyProgress
        for _ in 0..<50 { model.update(metrics) }
        XCTAssertEqual(model.journeyProgress, settled,
                       "a repeated identical metric must be a no-op")
    }

    // MARK: Galaxy backdrop

    /// The sky is scrubbed like everything else: same instant, same frame.
    func testGalaxyIsDeterministicAndParallaxed() {
        for index in [0, 5, 99] {
            let a = StoryGalaxy.star(index: index, t: 4.2, beat: 1)
            let b = StoryGalaxy.star(index: index, t: 4.2, beat: 1)
            XCTAssertEqual(a.position, b.position)
            XCTAssertEqual(a.brightness, b.brightness)
        }
        // Near layers must travel further against the scroll than far ones,
        // which is the whole depth cue.
        let far = StoryGalaxy.star(index: 0, t: 4.2, beat: 0).position.y
            - StoryGalaxy.star(index: 0, t: 4.2, beat: 5).position.y
        let near = StoryGalaxy.star(index: 2, t: 4.2, beat: 0).position.y
            - StoryGalaxy.star(index: 2, t: 4.2, beat: 5).position.y
        XCTAssertGreaterThan(near, far)
    }

    /// Meteors are rare by construction: a lane in flight at every instant
    /// would read as rain, not as a shooting star.
    func testMeteorLanesRestBetweenStreaks() {
        for index in 0..<StoryGalaxy.meteorCount {
            let flying = stride(from: 0.0, to: 20.0, by: 0.1)
                .filter { StoryGalaxy.meteor(index: index, t: $0) != nil }
            XCTAssertFalse(flying.isEmpty, "lane \(index) never fires")
            XCTAssertLessThan(Double(flying.count) / 200, 0.2,
                              "lane \(index) is in flight too often")
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
