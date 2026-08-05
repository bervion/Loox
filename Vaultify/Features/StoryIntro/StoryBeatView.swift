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

    var body: some View {
        VStack(spacing: Space.s5) {
            Spacer(minLength: 0)
            content
            Spacer(minLength: 0)
            if beat == .commitment {
                BrandCapsuleCTA(title: "Enter your vault", action: onComplete)
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
        case .commitment:
            title("Lock them in")
            body_("Loox remembers, so you can forget.")
        }
    }

    // MARK: Typography on the two canvases

    /// Dark-canvas beats keep fixed light text; themed beats read roles.
    private var primaryColor: Color {
        themed ? Color(rgb: theme.textPrimary) : StoryPalette.textPrimary
    }
    private var secondaryColor: Color {
        themed ? Color(rgb: theme.textSecondary) : StoryPalette.textSecondary
    }
    private var themed: Bool { beat == .sanctuary || beat == .commitment }

    private func title(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .vaultType(.largeTitle)
            .foregroundStyle(primaryColor)
            .multilineTextAlignment(.center)
            // Hero line only: blur entrance is the story's reveal verb, and
            // whole-block (never per-word) so VI and JA render identically.
            .scrollTransition(.interactive) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0)
                    .blur(radius: phase.isIdentity || reduceMotion ? 0 : 8)
                    .offset(y: phase.isIdentity || reduceMotion ? 0 : 24)
            }
    }

    private func body_(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .vaultType(.body)
            .foregroundStyle(secondaryColor)
            .multilineTextAlignment(.center)
            .scrollTransition(.interactive) { content, phase in
                content
                    .opacity(phase.isIdentity ? 1 : 0)
                    .offset(y: phase.isIdentity || reduceMotion ? 0 : 16)
            }
    }

    private func hint(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .vaultType(.callout)
            .foregroundStyle(secondaryColor)
            .phaseAnimator([false, true]) { content, pulsing in
                content.offset(y: pulsing && !reduceMotion ? -4 : 0)
            } animation: { _ in
                .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
            }
    }
}
