import SwiftUI

/// The story as a calm readable page: same copy, same exits, zero choreography.
/// Serves accessibility text sizes and VoiceOver (where six pinned full-height
/// pages would clip or read as noise), and doubles as the macOS presentation —
/// reflow, never shrink. The stage is a static poster: dark veil, one glow.
struct StoryIntroReaderView: View {
    let onComplete: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            poster

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Space.s8) {
                    section("Where do your passwords live?",
                            "Take a second and try to count them.")
                    section("A little bit of everywhere",
                            "Notes. Screenshots. That chat with yourself. A browser that keeps asking to save.",
                            "The more you clear, the more spill out")
                    section("One leak opens every door",
                            "Once it leaves, it never comes back.")
                    section("Now pull them back",
                            "You are gathering every stray password into one place.")
                    section("One vault. Yours alone.",
                            "Encrypted on this device. No account. Nothing leaves unless you say so.")
                    section("Lock them in",
                            "Loox remembers, so you can forget.")

                    BrandCapsuleCTA(title: "Enter your vault", action: onComplete)
                        .padding(.top, Space.s6)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.s10)
                .padding(.bottom, Space.s8)
                .vaultContentWidth(.form)
                .frame(maxWidth: .infinity)
            }

            Button(action: onSkip) {
                Text("Skip")
                    .vaultType(.callout)
                    .foregroundStyle(StoryPalette.textSecondary)
                    .padding(Space.s3)
                    .background(StoryPalette.controlScrim, in: Capsule())
                    .frame(minWidth: Metric.hitMin, minHeight: Metric.hitMin)
                    .contentShape(Rectangle())
            }
            .padding(.trailing, Space.gutter)
        }
    }

    /// Committed-dark poster, motion-free.
    private var poster: some View {
        ZStack {
            Color.black
            RadialGradient(colors: [StoryPalette.nebula.opacity(0.30), .clear],
                           center: .init(x: 0.35, y: 0.2),
                           startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func section(_ title: LocalizedStringKey,
                         _ bodies: LocalizedStringKey...) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .vaultType(.section)
                .foregroundStyle(StoryPalette.textPrimary)
            ForEach(Array(bodies.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .vaultType(.body)
                    .foregroundStyle(StoryPalette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
