import SwiftUI

/// One full-height page of the story's copy column. Beats 1–3 sit on the
/// committed-dark canvas and use the fixed StoryPalette; the turn rides the
/// canvas WHILE it resolves, so its copy crossfades between the fixed light
/// ink and the theme roles in lockstep with the surface; sanctuary and
/// commitment land after the theme has resolved and read semantic roles.
/// Entrances are render-side `scrollTransition`s (blur reserved for the hero
/// title alone), so they scrub with the user's finger and cost nothing at rest.
struct StoryBeatView: View {
    let beat: StoryBeat
    /// Beat 3's optional "send" tap (one-shot, forwarded to the stage).
    let onSendTap: () -> Void
    /// Beat 6's completion CTA.
    let onComplete: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Sanctuary's press-to-peek demo row.
    @State private var peeking = false

    /// Magazine display size for the beat titles — the story's hero voice,
    /// above the `largeTitle` role. Scaled off the largeTitle text style so
    /// it follows Dynamic Type until the reader presentation takes over.
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize: CGFloat = 46

    /// Fictional demo secret for the peek row — a constant, never user
    /// content, deliberately not localized.
    private static let demoSecret = "mQ4-vE81-kz"

    var body: some View {
        VStack(spacing: Space.s5) {
            // The stage's art (dot, ring, mark) lives in the upper part of the
            // frame around `StoryField.origin`; this fixed block biases the
            // copy toward the lower half so ink never sits inside the orbit.
            if artClearance > 0 {
                Color.clear
                    .containerRelativeFrame(.vertical) { length, _ in
                        length * artClearance
                    }
            }
            Spacer(minLength: 0)
            VStack(spacing: Space.s5) { content }
                .padding(.vertical, Space.s6)
                .padding(.horizontal, Space.s5)
                .background {
                    // Legibility vignette: a soft dark pool behind the copy
                    // block on the beats whose swarm drifts through the text
                    // zone. A scrim, not a material — glass stays reserved
                    // for controls, and a gradient costs nothing per frame.
                    // Consequence keeps it lighter so the glowing chip above
                    // the prompt still carries the scene.
                    if scrimStrength > 0 {
                        // Fully clear by 72% of the radius: the gradient must
                        // die INSIDE its own bounds or the frame's straight
                        // edges print as a faint box over the swarm.
                        EllipticalGradient(
                            stops: [
                                .init(color: Color.black.opacity(scrimStrength), location: 0),
                                .init(color: .clear, location: 0.72),
                            ],
                            center: .center,
                            startRadiusFraction: 0.28,
                            endRadiusFraction: 1.0)
                    }
                }
            Spacer(minLength: 0)
            if beat == .commitment {
                StorySealCTA(title: "Hold to enter your vault", onSealed: onComplete)
                    .padding(.bottom, Space.s8)
            }
        }
        .padding(.horizontal, Space.gutter)
        .vaultContentWidth(.form)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if beat == .consequence { onSendTap() }
        }
    }

    /// Fraction of the page height reserved above the copy. The sanctuary and
    /// commitment pages sit under the full cluster, the turn under the closing
    /// orbits, the hook under the dot's halo alone.
    ///
    /// The cluster pages take theirs from `StoryOrbitLattice`, the same numbers
    /// that bound how far down the frame the art may grow. Two independent
    /// constants is how the sigils ended up sweeping through the sanctuary
    /// title on a small phone: one of them moved and the other did not.
    private var artClearance: Double {
        switch beat {
        case .chaos, .consequence: return 0
        case .hook: return 0.06 * largeTextRelief
        // The turn has the bubbles but not yet the sigils, so it clears to the
        // outermost BUBBLE. Its copy is two short lines, so it never needs the
        // large-text relief — and taking it would put the title inside solid
        // brand colour rather than behind a faint arc.
        case .turn: return StoryOrbitLattice.bubbleFloor
        case .sanctuary, .commitment: return StoryOrbitLattice.artFloor * largeTextRelief
        }
    }

    /// Peak opacity of the legibility vignette behind this beat's copy. Only
    /// the dark-world swarm beats need one; the other pages keep their art
    /// clear of the text zone by layout.
    private var scrimStrength: Double {
        switch beat {
        case .chaos: 0.45
        case .consequence: 0.28
        default: 0
        }
    }

    /// At large Dynamic Type the clearance yields before the copy does: text
    /// that is clipped is worse than text overlapping a faint arc, and past
    /// `.accessibility1` the reader presentation takes over entirely.
    private var largeTextRelief: Double { dynamicTypeSize >= .xxLarge ? 0.55 : 1 }

    @ViewBuilder private var content: some View {
        switch beat {
        case .hook:
            title("Where do your passwords live?")
            body_("Take a second and try to count them.")
            hint("Scroll", chevron: true)
                .padding(.top, Space.s8)
        case .chaos:
            title("A little bit of everywhere")
            body_("Notes. Screenshots. That chat with yourself. A browser that keeps asking to save.")
            body_("The more you clear, the more spill out", entranceDrop: 28)
                .padding(.top, Space.s4)
        case .consequence:
            title("One leak opens every door")
            // Room for the shared chip glowing at the stage's centre — the
            // prompt sits just beneath it.
            Spacer().frame(height: Space.s10)
            hint("Tap to send it, like we all do")
            body_("Once it leaves, it never comes back.", entranceDrop: 28)
                .padding(.top, Space.s4)
        case .turn:
            title("Now pull them back", resolvesWithCanvas: true)
            body_("Keep scrolling. You are gathering every stray password into one place.",
                  resolvesWithCanvas: true)
        case .sanctuary:
            title("One vault. Yours alone.")
            body_("Encrypted on this device. No account. Nothing leaves unless you say so.")
            peekRow
                .padding(.top, Space.s6)
        case .commitment:
            title("Lock them in")
            body_("Loox remembers, so you can forget.")
        }
    }

    // MARK: Typography on the two canvases

    /// Dark-canvas beats keep fixed light text; themed beats read roles.
    private var primaryColor: Color {
        themed ? theme.color(.primary) : StoryPalette.textPrimary
    }
    private var secondaryColor: Color {
        themed ? theme.color(.secondary) : StoryPalette.textSecondary
    }
    private var themed: Bool { beat == .sanctuary || beat == .commitment }

    /// `resolvesWithCanvas` is the turn page's contract: the canvas beneath it
    /// crossfades dark→theme WHILE this copy is entering, so a single fixed
    /// ink is wrong at one end or the other (fixed white vanished on light
    /// themes the moment the mix completed). Two stacked layers with
    /// complementary opacities track the surface exactly, driven by the same
    /// scroll phase that drives the mix — still render-side, no model reads.
    private func title(_ key: LocalizedStringKey,
                       resolvesWithCanvas: Bool = false) -> some View {
        ZStack {
            // The sanctuary and commitment beats land AFTER the canvas has
            // resolved into the user's theme, so their bloom is the accent at a
            // whisper: the fixed cool glow is invisible on a light background,
            // and on a dark one it would flip hue mid-story.
            titleLayer(key, ink: primaryColor,
                       glow: themed ? Color(rgb: theme.accentFill) : StoryPalette.titleGlow,
                       glowStrength: themed ? Self.themedGlow : Self.darkGlow,
                       fade: resolvesWithCanvas ? .fixedInk : .none)
            if resolvesWithCanvas {
                // The turn's second layer lands on the user's own background,
                // where a cold bloom would be a smudge — it takes the accent at
                // a fraction of the strength instead.
                titleLayer(key, ink: theme.color(.primary),
                           glow: Color(rgb: theme.accentFill),
                           glowStrength: Self.themedGlow, fade: .themedInk)
            }
        }
    }

    /// Bloom strength on the committed-dark canvas, and on the user's own
    /// (possibly light) background once the story has resolved into it.
    private static let darkGlow = 0.55
    private static let themedGlow = 0.18

    private func titleLayer(_ key: LocalizedStringKey, ink: Color, glow: Color,
                            glowStrength: Double, fade: CanvasFade) -> some View {
        Text(key)
            // Magazine hero voice: SF at its heaviest above the largeTitle
            // role, tightened a touch — short lines carry the page like a
            // cover. Tracking stays modest because VI stacks diacritics above
            // the cap height and JA falls back to Hiragino, neither of which
            // survives the tight tracking a Latin-only cover would take.
            .font(.vaultDisplay(size: displaySize))
            .kerning(-0.6)
            // The longest VI/JA title at black display on a 375pt phone wraps
            // to three lines; a floor keeps the magazine cut without ever
            // shrinking into illegibility.
            .minimumScaleFactor(0.75)
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            // Two-stop bloom: a wide halo for the light-off-the-page read, a
            // tight one to keep the counters from washing out. Part of the
            // content, so the entrance fades and blurs it in lockstep.
            .shadow(color: glow.opacity(glowStrength), radius: 18)
            .shadow(color: glow.opacity(glowStrength * 0.55), radius: 5)
            // Hero line only: blur entrance is the story's reveal verb, and
            // whole-block (never per-word) so VI and JA render identically.
            // Interpolated on phase.VALUE, not `isIdentity`: with full-height
            // pages that flag is true only at the snapped rest position, so a
            // boolean would hard-blink the copy away the instant a drag begins
            // instead of scrubbing with the finger.
            .scrollTransition(.interactive) { [reduceMotion] content, phase in
                content
                    .opacity(Self.nearness(phase) * fade.weight(phase))
                    .blur(radius: reduceMotion ? 0 : 8 * (1 - Self.nearness(phase)))
                    .offset(y: reduceMotion ? 0 : 24 * (1 - Self.nearness(phase)))
            }
    }

    /// `entranceDrop` staggers sibling lines: a later line rises from deeper,
    /// so a page's copy arrives as layered depth instead of one flat slab.
    private func body_(_ key: LocalizedStringKey, entranceDrop: CGFloat = 16,
                       resolvesWithCanvas: Bool = false) -> some View {
        ZStack {
            bodyLayer(key, ink: secondaryColor, entranceDrop: entranceDrop,
                      fade: resolvesWithCanvas ? .fixedInk : .none)
            if resolvesWithCanvas {
                bodyLayer(key, ink: theme.color(.secondary),
                          entranceDrop: entranceDrop, fade: .themedInk)
            }
        }
    }

    private func bodyLayer(_ key: LocalizedStringKey, ink: Color,
                           entranceDrop: CGFloat, fade: CanvasFade) -> some View {
        Text(key)
            .vaultType(.body)
            // A step up from regular: body copy on a moving cinematic canvas
            // needs more stem than the same size does on a settled screen.
            .fontWeight(.medium)
            .foregroundStyle(ink)
            .multilineTextAlignment(.center)
            .scrollTransition(.interactive) { [reduceMotion] content, phase in
                content
                    .opacity(Self.nearness(phase) * fade.weight(phase))
                    .offset(y: reduceMotion ? 0 : entranceDrop * (1 - Self.nearness(phase)))
            }
    }

    /// How a copy layer weighs itself against the canvas crossfade.
    private enum CanvasFade {
        /// Single-ink copy: full weight, the phase only drives the entrance.
        case none
        /// The dark-world ink: fades OUT as the canvas resolves.
        case fixedInk
        /// The theme ink: fades IN as the canvas resolves.
        case themedInk

        nonisolated func weight(_ phase: ScrollTransitionPhase) -> Double {
            switch self {
            case .none: 1
            case .fixedInk: 1 - StoryBeatView.canvasResolve(phase)
            case .themedInk: StoryBeatView.canvasResolve(phase)
            }
        }
    }

    /// 1 on the resting page, easing to 0 a full page away.
    ///
    /// `nonisolated` and the `[reduceMotion]` capture lists above are load
    /// bearing: `scrollTransition`'s closure is `@Sendable`, so it does not
    /// inherit this View's MainActor isolation. Without both, the closures
    /// raise nine concurrency warnings that become errors under Swift 6.
    nonisolated private static func nearness(_ phase: ScrollTransitionPhase) -> Double {
        1 - min(abs(phase.value), 1)
    }

    /// The stage's dark→theme mix as seen from the TURN page's own scroll
    /// phase. The page rests at beat 3 and its phase.value runs +1→0 while
    /// entering, so `beat = 3 − value` — the same coordinate the stage feeds
    /// into its resolve window. Keeping the mapping here (not a model read)
    /// leaves the beat column untouched by scroll ticks.
    nonisolated private static func canvasResolve(_ phase: ScrollTransitionPhase) -> Double {
        StoryField.smoothstep(3 - phase.value,
                              StoryStageView.themeResolveStart,
                              StoryStageView.themeResolveEnd)
    }

    /// The product's Controlled Reveal physics taught as play: secrets open
    /// only under your finger, and hide the instant you let go.
    private var peekRow: some View {
        VStack(spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                VaultIcon(Icons.key, size: Metric.iconCompact)
                    .themedForeground(.iconSecondary)
                GlyphResolveText(text: Self.demoSecret, isRevealed: peeking)
                Spacer(minLength: 0)
                VaultIcon(peeking ? Icons.reveal : Icons.hide, size: Metric.iconCompact)
                    .themedForeground(.iconSecondary)
            }
            .padding(Space.s4)
            .background(Color(rgb: theme.controlBackground))
            .vaultCornerRadius(Radius.md)
            .overlay { peekPing }
            .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 44,
                                perform: {},
                                onPressingChanged: { pressing in
                                    peeking = pressing
                                    // One tap as the secret opens; letting go
                                    // is the absence of feedback, which is the
                                    // point — nothing was committed.
                                    if pressing { Haptics.tap() }
                                })
            .accessibilityRepresentation {
                Toggle("Peek at the example secret", isOn: $peeking)
            }

            Text(peeking ? "Let go and it hides again" : "Hold a row to peek")
                .vaultType(.footnote)
                .foregroundStyle(secondaryColor)
        }
        .scrollTransition(.interactive) { content, phase in
            content.opacity(Self.nearness(phase))
        }
    }

    /// A slow accent sonar around the peek row: the ring swells off the row's
    /// edge and dissolves, naming "touch and hold me" without words. Retired
    /// the moment the user peeks (the affordance has done its job) and absent
    /// under Reduce Motion.
    private enum PingPhase: CaseIterable { case hidden, armed, fired }

    @ViewBuilder private var peekPing: some View {
        if !reduceMotion && !peeking {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Color(rgb: theme.accentFill), lineWidth: 1.5)
                .allowsHitTesting(false)
                .phaseAnimator(PingPhase.allCases) { ring, phase in
                    ring
                        .opacity(phase == .armed ? 0.55 : 0)
                        .scaleEffect(phase == .fired ? 1.07 : 1)
                } animation: { target in
                    switch target {
                    // Arm instantly (invisible-to-visible at rest scale)…
                    case .armed: .linear(duration: 0.01)
                    // …swell and fade off the edge…
                    case .fired: .easeOut(duration: 1.0)
                    // …then dwell dark before the next ping.
                    case .hidden: .linear(duration: 1.6)
                    }
                }
        }
    }

    /// An instructional cue. With `chevron`, a rising glyph names the gesture's
    /// direction above the label — the story's pages advance with an upward
    /// pull, and words alone were not landing it.
    @ViewBuilder private func hint(_ key: LocalizedStringKey,
                                   chevron: Bool = false) -> some View {
        let base = VStack(spacing: Space.s1) {
            if chevron {
                VaultIcon(Icons.chevronDown, size: Metric.iconInline)
                    .rotationEffect(.degrees(180))
            }
            Text(key)
                .vaultType(.callout)
        }
        .foregroundStyle(secondaryColor)
        if reduceMotion {
            // The animator is not attached at all. `Animation.vault` returning
            // nil is the right token for `.animation(_:value:)`, NOT for a phase
            // driver: a nil animation makes each phase transition INSTANT rather
            // than absent, so the offset would flip continuously — the opposite
            // of what Reduce Motion asks for.
            base
        } else {
            // The lift and the brightening breathe together — a quiet beacon,
            // not a bouncing arrow.
            base.phaseAnimator([false, true]) { content, pulsing in
                content
                    .offset(y: pulsing ? -4 : 0)
                    .opacity(pulsing ? 1 : 0.55)
            } animation: { _ in
                .easeInOut(duration: Motion.slow * 3).repeatForever(autoreverses: true)
            }
        }
    }
}
