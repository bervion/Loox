import SwiftUI

/// First-launch Security surface: when the active persona has no items there is
/// nothing to score, so the misleading "At risk" ring and 100% strength bar give
/// way to a full-bleed plain-canvas screen — the brand swirl fronting the
/// security shield (playing once), a short line, and a single CTA into the editor.
struct WatchtowerEmptyStateView: View {
    let onAdd: () -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Largest the artwork may get. It shrinks with the pane so a narrow Split View
    /// column keeps the swirl inside its own width instead of clipping it.
    private static let artworkMax: CGFloat = 176

    /// `WatchtowerScreen` floats its header over this view, so scrolled content must
    /// start below it — the same clearance `VaultHeaderScrollSpacer` reserves.
    private static let headerClearance = Space.s6 + Metric.hitMin

    var body: some View {
        ZStack {
            // Plain canvas (white in light, near-black in dark) — the swirl reads
            // like the QR / biometric onboarding screens, not the grouped gray tab.
            Color(rgb: env.theme.active.background).ignoresSafeArea()

            // Scrollable: at accessibility sizes with the longest VI strings the copy
            // plus the CTA outgrows an SE screen, and the old fixed VStack stranded the
            // button off-screen with no way to reach it.
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: Space.s6) {
                        Spacer(minLength: Self.headerClearance)
                        content(width: proxy.size.width)
                        Spacer(minLength: Space.s6)
                        cta
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, Space.s8)
                    // Fills the viewport when the content is short (the Spacers centre
                    // it, as before) and grows past it when the content is tall.
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
    }

    private func content(width: CGFloat) -> some View {
        // Shrinks with the pane, and again at accessibility sizes where the text needs
        // the vertical room more than the brand mark does. The swirl lays itself out in
        // fractions of its frame, so a smaller box is a faithful smaller drawing.
        let fitted = min(Self.artworkMax, max(96, width * 0.45))
        let artwork = dynamicTypeSize.isAccessibilitySize ? fitted * 0.7 : fitted
        return VStack(spacing: Space.s6) {
            // One-shot reveal fronting the security shield, tinted to the accent.
            // Decorative: the copy below already carries the meaning.
            LooxSwirlAnimationView(mode: .reveal,
                                   centerIcon: "dt_shield_keyhole",
                                   centerTint: env.theme.active.color(.accent))
                .frame(width: artwork, height: artwork)
                .accessibilityHidden(true)

            VStack(spacing: Space.s2) {
                Text("Nothing to protect yet")
                    .vaultType(.headline)
                    .themedForeground(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Add your first password and Loox starts watching over your vault's security.")
                    .vaultType(.subhead)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cta: some View {
        Button(action: onAdd) {
            HStack(spacing: Space.s2) {
                VaultIcon(Icons.pageAdd, size: Metric.iconInline)
                Text("Add your first password")
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.themedProminent)
    }
}

/// Neutral gauge shown when the vault HAS items but no audit has completed yet:
/// the real ring would count up to a red "At risk" zero, which is a verdict we
/// have not earned. A muted 270° track with an em dash reads as "unknown, run a
/// check" — matching the real ring's 135°/270° geometry so nothing jumps when
/// the first audit finishes.
struct WatchtowerPendingRing: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let track = Color(rgb: env.theme.active.separator)
        VStack(spacing: Space.s2) {
            ZStack {
                Circle()
                    .trim(from: 0, to: 0.75)
                    .rotation(.degrees(135))
                    .stroke(track, style: StrokeStyle(lineWidth: 30, lineCap: .round))
                    .frame(width: 212, height: 212)
                Text(verbatim: "—")
                    .vaultType(.largeTitle)
                    .themedForeground(.tertiary)
            }
            // 270° gauge leaves a bottom gap; pull the caption up into it.
            .frame(height: 190, alignment: .top)

            Text("Not checked yet")
                .vaultType(.footnote)
                .themedForeground(.tertiary)
        }
    }
}
