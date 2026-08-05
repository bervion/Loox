import SwiftUI

/// One-time cinematic story intro: shown by RootView INSTEAD of the app while
/// `storyIntroCompleted` is false, so HomeScreen never mounts and the firstRun
/// tutorial cannot start underneath (it arrives on its own once the flag flips
/// and Home appears). Six full-height beats on one continuous vertical scroll;
/// completing or skipping sets the flag and the route crossfade lands on Home.
///
/// Phase 1 skeleton: beat scaffolding, skip/complete wiring, analytics.
/// The stage layer (particles, veil, dark→theme crossfade) lands in phase 2,
/// beat choreography in phases 3–4 (see plans/260805-1404-onboarding-story-intro).
struct StoryIntroScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var visibleBeat: Int?
    /// Highest beat reached, for the `story_intro_ended` analytics event.
    @State private var furthestBeat = StoryBeat.hook.rawValue

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Committed-dark cinematic canvas in BOTH appearance modes (owner
            // decision; brand-animation fixed-color precedent). The phase-02
            // stage veil replaces this flat fill and handles the beat-4
            // crossfade into the user's theme background.
            Color.black.ignoresSafeArea()

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(StoryBeat.allCases) { beat in
                        StoryBeatPlaceholderView(beat: beat) {
                            complete(outcome: "completed")
                        }
                        .containerRelativeFrame(.vertical)
                        .id(beat.rawValue)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $visibleBeat)
            .onChange(of: visibleBeat) { _, beat in
                if let beat { furthestBeat = max(furthestBeat, beat) }
            }

            skipButton
        }
        .analyticsScreen("story_intro")
    }

    private var skipButton: some View {
        Button {
            complete(outcome: "skipped")
        } label: {
            Text("Skip")
                .vaultType(.callout)
                .foregroundStyle(StoryPalette.textSecondary)
                .padding(Space.s3) // pads the label out to a 44pt hit area
        }
        .padding(.trailing, Space.gutter)
    }

    /// Single exit: BOTH finish and skip set the completion flag (never show
    /// the story twice), and only a real completion earns the arrival-bridge
    /// hint (Home's one-shot Add-button pulse after the firstRun tutorial).
    /// The route change animates via RootView's existing crossfade.
    private func complete(outcome: String) {
        AnalyticsEngine.shared.log(.storyIntroEnded(outcome: outcome,
                                                    furthestBeat: furthestBeat))
        if outcome == "completed" {
            env.settings.storyIntroWantsFirstItem = true
        }
        env.settings.storyIntroCompleted = true
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
/// layers use fixed decorative color. Beats 4–6 switch to semantic roles once
/// the phase-02 stage crossfades the canvas into the user's theme.
enum StoryPalette {
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
}

/// Phase-1 placeholder for a beat page: title copy only, plus the completion
/// CTA on the final beat. Replaced beat-by-beat in phases 3–4.
private struct StoryBeatPlaceholderView: View {
    let beat: StoryBeat
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: Space.s6) {
            Spacer()
            title
                .vaultType(.largeTitle)
                .foregroundStyle(StoryPalette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.gutter)
            Spacer()
            if beat == .commitment {
                BrandCapsuleCTA(title: "Enter your vault", action: onComplete)
            }
        }
        .vaultContentWidth(.form)
        .frame(maxWidth: .infinity)
    }

    private var title: Text {
        switch beat {
        case .hook: Text("Where do your passwords live?")
        case .chaos: Text("A little bit of everywhere")
        case .consequence: Text("One leak opens every door")
        case .turn: Text("Now pull them back")
        case .sanctuary: Text("One vault. Yours alone.")
        case .commitment: Text("Lock them in")
        }
    }
}
