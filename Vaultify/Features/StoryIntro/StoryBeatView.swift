import SwiftUI

/// One full-height page of the story's copy column. Beats 1–4 sit on the
/// committed-dark canvas and use the fixed StoryPalette; sanctuary and
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
    /// Sanctuary's press-to-peek demo row.
    @State private var peeking = false

    /// Fictional demo secret for the peek row — a constant, never user
    /// content, deliberately not localized.
    private static let demoSecret = "mQ4-vE81-kz"

    var body: some View {
        VStack(spacing: Space.s5) {
            Spacer(minLength: 0)
            content
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

    @ViewBuilder private var content: some View {
        switch beat {
        case .hook:
            title("Where do your passwords live?")
            body_("Take a second and try to count them.")
            hint("Scroll")
                .padding(.top, Space.s8)
        case .chaos:
            title("A little bit of everywhere")
            body_("Notes. Screenshots. That chat with yourself. A browser that keeps asking to save.")
            body_("The more you clear, the more spill out")
                .padding(.top, Space.s4)
        case .consequence:
            title("One leak opens every door")
            // Room for the shared chip glowing at the stage's centre — the
            // prompt sits just beneath it.
            Spacer().frame(height: Space.s10)
            hint("Tap to send it, like we all do")
            body_("Once it leaves, it never comes back.")
                .padding(.top, Space.s4)
        case .turn:
            title("Now pull them back")
            body_("Keep scrolling. You are gathering every stray password into one place.")
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

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .vaultType(.largeTitle)
            .foregroundStyle(primaryColor)
            .multilineTextAlignment(.center)
            // Hero line only: blur entrance is the story's reveal verb, and
            // whole-block (never per-word) so VI and JA render identically.
            // Interpolated on phase.VALUE, not `isIdentity`: with full-height
            // pages that flag is true only at the snapped rest position, so a
            // boolean would hard-blink the copy away the instant a drag begins
            // instead of scrubbing with the finger.
            .scrollTransition(.interactive) { [reduceMotion] content, phase in
                content
                    .opacity(Self.nearness(phase))
                    .blur(radius: reduceMotion ? 0 : 8 * (1 - Self.nearness(phase)))
                    .offset(y: reduceMotion ? 0 : 24 * (1 - Self.nearness(phase)))
            }
    }

    private func body_(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .vaultType(.body)
            .foregroundStyle(secondaryColor)
            .multilineTextAlignment(.center)
            .scrollTransition(.interactive) { [reduceMotion] content, phase in
                content
                    .opacity(Self.nearness(phase))
                    .offset(y: reduceMotion ? 0 : 16 * (1 - Self.nearness(phase)))
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
            .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 44,
                                perform: {},
                                onPressingChanged: { peeking = $0 })
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

    @ViewBuilder private func hint(_ key: LocalizedStringKey) -> some View {
        let base = Text(key)
            .vaultType(.callout)
            .foregroundStyle(secondaryColor)
        if reduceMotion {
            // The animator is not attached at all. `Animation.vault` returning
            // nil is the right token for `.animation(_:value:)`, NOT for a phase
            // driver: a nil animation makes each phase transition INSTANT rather
            // than absent, so the offset would flip continuously — the opposite
            // of what Reduce Motion asks for.
            base
        } else {
            base.phaseAnimator([false, true]) { content, pulsing in
                content.offset(y: pulsing ? -4 : 0)
            } animation: { _ in
                .easeInOut(duration: Motion.slow * 3).repeatForever(autoreverses: true)
            }
        }
    }
}
