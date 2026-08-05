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
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: StoryScrollMetricsKey.self,
                            value: StoryScrollMetrics(
                                offset: -proxy.frame(in: .named(Self.scrollSpace)).minY,
                                span: proxy.size.height * 5 / 6))
                    }
                }
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $visibleBeat)
            .coordinateSpace(name: Self.scrollSpace)
            .onPreferenceChange(StoryScrollMetricsKey.self) { progress.update($0) }
            .onChange(of: visibleBeat) { _, beat in
                if let beat { furthestBeat = max(furthestBeat, beat) }
            }

            skipButton
        }
    }

    private static let scrollSpace = "story-scroll"
    /// `furthest_beat` value meaning "the reader presentation was used", which
    /// has no per-beat progress to report.
    private static let readerBeatSentinel = 0

    private var skipButton: some View {
        Button {
            complete(outcome: "skipped")
        } label: {
            Text("Skip")
                .vaultType(.callout)
                .foregroundStyle(StoryPalette.textSecondary)
                .padding(Space.s3)
                // The story's only exit rides over a canvas that resolves into
                // the user's theme, so a fixed light label needs its own
                // surface to keep contrast on a light background.
                .background(StoryPalette.controlScrim, in: Capsule())
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

/// Fixed colors for text sitting on the committed-dark canvas — the one place
/// the story does not read theme roles, mirroring how the brand-animation
/// layers use fixed decorative color. The sanctuary and commitment beats
/// switch to semantic roles once the stage has resolved into the theme.
enum StoryPalette {
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let glow = Color(red: 0.62, green: 0.74, blue: 1.0).opacity(0.55)
    static let nebula = Color(red: 0.30, green: 0.40, blue: 0.72)
    static let nebulaDeep = Color(red: 0.22, green: 0.24, blue: 0.52)
    static let scrapFill = Color.white.opacity(0.08)
    static let scrapStroke = Color.white.opacity(0.14)
    /// Surface behind the fixed-light Skip label, so it survives the canvas
    /// resolving into a light theme.
    static let controlScrim = Color.black.opacity(0.35)
    /// Consequence tinge: warm amber, deliberately short of red horror.
    static let warning = Color(red: 0.95, green: 0.62, blue: 0.30)
}

