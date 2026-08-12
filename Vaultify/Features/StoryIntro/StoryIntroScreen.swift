import SwiftUI

/// One-time cinematic story intro: shown by RootView INSTEAD of the app while
/// `storyIntroCompleted` is false, so HomeScreen never mounts and the firstRun
/// tutorial cannot start underneath (it arrives on its own once the flag flips
/// and Home appears). Six full-height beats on one continuous vertical scroll;
/// completing or skipping sets the flag and the route crossfade lands on Home.
///
/// Accessibility sizes and VoiceOver swap the pinned journey for
/// `StoryIntroReaderView` (same copy, same exits, zero choreography).
struct StoryIntroScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverOn
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var visibleBeat: Int?
    /// Highest beat reached, for the `story_intro_ended` analytics event.
    @State private var furthestBeat = StoryBeat.hook.rawValue
    /// Read by the stage layer only — scroll writes never touch this view's
    /// own state, so the beat column is not re-evaluated per scroll tick.
    @State private var progress = StoryScrollProgressModel()
    /// An exit is already under way (guards the 650ms seal-burst window).
    @State private var exiting = false

    var body: some View {
        Group {
            if useReader {
                // Reflow, never shrink: at accessibility sizes, under
                // VoiceOver, and on macOS the pinned full-height pages give
                // way to a plain readable page with the same copy and exits.
                // The reader shows every beat's copy on one page, so reaching
                // its CTA genuinely means the whole story was presented. A
                // skip has no per-beat progress to report, so it files the
                // reader sentinel rather than looking like a bail-out at the
                // hook (which is what beat 1 would mean on the journey).
                StoryIntroReaderView(
                    onComplete: {
                        furthestBeat = StoryBeat.commitment.rawValue
                        complete(outcome: "completed", playExit: false)
                    },
                    onSkip: {
                        furthestBeat = Self.readerBeatSentinel
                        complete(outcome: "skipped")
                    })
            } else {
                journey
            }
        }
        .analyticsScreen("story_intro")
    }

    private var useReader: Bool {
        #if os(macOS)
        // Scroll-scrubbing and a timed mouse-hold feel poor with a pointer;
        // researcher-06 found even Arc/Dia use windowed discrete steps, not
        // full-screen cinema. A dedicated stepped window remains a follow-up.
        return true
        #else
        return dynamicTypeSize >= .accessibility1 || voiceOverOn
        #endif
    }

    private var journey: some View {
        ZStack(alignment: .topTrailing) {
            // Committed-dark cinematic canvas in BOTH appearance modes (owner
            // decision; brand-animation fixed-color precedent), cross-fading
            // into the user's theme across the turn beat.
            StoryStageView(model: progress)

            beatColumn
                .onChange(of: visibleBeat) { _, beat in
                    if let beat { furthestBeat = max(furthestBeat, beat) }
                }

            skipButton
        }
    }

    /// Scroll-progress plumbing splits by OS: `onScrollGeometryChange` is the
    /// supported feed on iOS 18+, and on those runtimes it is also the ONLY
    /// working one — a `GeometryReader` in the content's background stops
    /// re-measuring during scrolls there, which froze `beatPosition` at 0 and
    /// silently killed the whole stage (no swarm, no gather, no theme resolve).
    /// The preference pipeline stays solely for the 17.3 floor.
    @ViewBuilder private var beatColumn: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            pagedScroll(legacyMetrics: false)
                .onScrollGeometryChange(for: StoryScrollMetrics.self) { geometry in
                    StoryScrollMetrics(
                        offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        span: geometry.contentSize.height - geometry.containerSize.height)
                } action: { _, metrics in
                    progress.update(metrics)
                }
        } else {
            pagedScroll(legacyMetrics: true)
                .coordinateSpace(name: Self.scrollSpace)
                .onPreferenceChange(StoryScrollMetricsKey.self) { progress.update($0) }
        }
    }

    private func pagedScroll(legacyMetrics: Bool) -> some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(StoryBeat.allCases) { beat in
                    StoryBeatView(beat: beat,
                                  onSendTap: { progress.noteSendTap() },
                                  onComplete: { complete(outcome: "completed") })
                        .containerRelativeFrame(.vertical)
                        .id(beat.rawValue)
                }
            }
            .scrollTargetLayout()
            .background {
                // One measurement serves both numbers: the column is six
                // equal `containerRelativeFrame` pages, so the scrollable
                // span is exactly five sixths of the content height.
                if legacyMetrics {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: StoryScrollMetricsKey.self,
                            value: StoryScrollMetrics(
                                offset: -proxy.frame(in: .named(Self.scrollSpace)).minY,
                                span: proxy.size.height * 5 / 6))
                    }
                }
            }
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $visibleBeat)
    }

    private static let scrollSpace = "story-scroll"
    /// `furthest_beat` value meaning "the reader presentation was used", which
    /// has no per-beat progress to report.
    private static let readerBeatSentinel = 0

    private var skipButton: some View {
        StorySkipButton(model: progress, exiting: exiting) {
            complete(outcome: "skipped")
        }
    }

    /// Single exit: BOTH finish and skip set the completion flag (never show
    /// the story twice), and only a real completion earns the arrival-bridge
    /// hint (Home's one-shot Add-button pulse after the firstRun tutorial).
    /// The route change animates via RootView's existing crossfade.
    /// `playExit` is false for the reader, which has no stage to burst — it
    /// would only add dead time before the hand-off.
    private func complete(outcome: String, playExit: Bool = true) {
        // One exit per session: the seal's burst keeps the screen alive for
        // 650ms, and a Skip landing in that window would emit a second
        // `story_intro_ended` contradicting the first.
        guard !exiting else { return }
        exiting = true
        AnalyticsEngine.shared.log(.storyIntroEnded(outcome: outcome,
                                                    furthestBeat: furthestBeat))
        guard outcome == "completed" else {
            env.settings.storyIntroCompleted = true
            return
        }
        env.settings.storyIntroWantsFirstItem = true
        guard playExit, !reduceMotion else {
            env.settings.storyIntroCompleted = true
            return
        }
        // Sealed by hand: let the stage's exit burst play, then flip the flag
        // so the route crossfade lands on Home as the bloom settles.
        progress.noteSeal()
        Task {
            try? await Task.sleep(for: .milliseconds(650))
            env.settings.storyIntroCompleted = true
        }
    }
}

/// The six story beats, in scroll order. `rawValue` doubles as the scroll
/// position id and the `furthest_beat` analytics value (1...6).
enum StoryBeat: Int, CaseIterable, Identifiable {
    case hook = 1, chaos, consequence, turn, sanctuary, commitment
    var id: Int { rawValue }
}

/// The story's only chrome control, split into its own view so the per-tick
/// `beatPosition` read invalidates this one capsule and never the beat column.
/// The label rides a canvas that resolves from committed-dark into the user's
/// theme, so its colors blend along the same window: fixed light-on-scrim in
/// the dark world, themed secondary-on-control once the light has returned.
private struct StorySkipButton: View {
    let model: StoryScrollProgressModel
    let exiting: Bool
    let action: () -> Void

    @Environment(\.appTheme) private var theme

    private var mix: Double {
        StoryField.smoothstep(model.beatPosition, StoryStageView.themeResolveStart,
                              StoryStageView.themeResolveEnd)
    }

    var body: some View {
        Button(action: action) {
            Text("Skip")
                .vaultType(.callout)
                .foregroundStyle(Color(rgb: RGBMath.blend(0xFFFFFF, theme.secondaryText, mix))
                    .opacity(0.7 + 0.3 * mix))
                .padding(Space.s3)
                .background(
                    Color(rgb: RGBMath.blend(0x000000, theme.controlBackground, mix))
                        .opacity(0.35 + 0.65 * mix),
                    in: Capsule())
                // Hold the 44pt floor at every Dynamic Type size, including
                // the smallest, where the label alone falls short.
                .frame(minWidth: Metric.hitMin, minHeight: Metric.hitMin)
                .contentShape(Rectangle())
        }
        .padding(.trailing, Space.gutter)
        // The seal's exit burst is playing; skipping now would log a second,
        // contradicting outcome for the same session.
        .disabled(exiting)
        .opacity(exiting ? 0 : 1)
    }
}

/// Fixed colors for text sitting on the committed-dark canvas — the one place
/// the story does not read theme roles, mirroring how the brand-animation
/// layers use fixed decorative color. The sanctuary and commitment beats
/// switch to semantic roles once the stage has resolved into the theme.
enum StoryPalette {
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    /// The origin dot's aura: a cool halo, deliberately shy of a headlight —
    /// it shares the frame with the hook's title.
    static let glow = Color(red: 0.62, green: 0.74, blue: 1.0).opacity(0.45)
    /// Bloom behind the display titles. Cool rather than white: pure white
    /// bloom on white ink just fattens the glyphs, while a cold cast reads as
    /// light coming off the page — the magazine-cover note, at a whisper.
    static let titleGlow = Color(red: 0.60, green: 0.78, blue: 1.0)
    static let scrapFill = Color.white.opacity(0.10)
    static let scrapStroke = Color.white.opacity(0.18)
    static let scrapGlyph = Color.white.opacity(0.78)
    /// Surface behind the reader presentation's fixed-light Skip label (its
    /// poster never resolves into the theme, so a static scrim is enough
    /// there; the journey's Skip blends live instead).
    static let controlScrim = Color.black.opacity(0.35)
    /// Consequence tinge: warm amber, deliberately short of red horror.
    static let warning = Color(red: 0.95, green: 0.62, blue: 0.30)
}

