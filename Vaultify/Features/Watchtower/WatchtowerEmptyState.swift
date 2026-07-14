import SwiftUI

/// First-launch Security surface: when the active persona has no items there is
/// nothing to score, so the misleading "At risk" ring and 100% strength bar give
/// way to a full-bleed plain-canvas screen — the brand swirl fronting the
/// security shield (playing once), a short line, and a single CTA into the editor.
struct WatchtowerEmptyStateView: View {
    let onAdd: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            // Plain canvas (white in light, near-black in dark) — the swirl reads
            // like the QR / biometric onboarding screens, not the grouped gray tab.
            Color(rgb: env.theme.active.background).ignoresSafeArea()

            VStack(spacing: Space.s6) {
                Spacer()
                // One-shot reveal fronting the security shield, tinted to the accent.
                LooxSwirlAnimationView(mode: .reveal,
                                       centerIcon: "dt_shield_keyhole",
                                       centerTint: env.theme.active.color(.accent))
                    .frame(width: 176, height: 176)

                VStack(spacing: Space.s2) {
                    Text("Nothing to protect yet")
                        .vaultType(.headline)
                        .themedForeground(.primary)
                    Text("Add your first password and Loox starts watching over your vault's security.")
                        .vaultType(.subhead)
                        .themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Space.s6)
                }

                Spacer()

                Button(action: onAdd) {
                    HStack(spacing: Space.s2) {
                        PolarisIcon(Icons.pageAdd, size: Metric.iconInline)
                        Text("Add your first password")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s8)
            }
        }
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
                    .stroke(track, style: StrokeStyle(lineWidth: 26, lineCap: .round))
                    .frame(width: 196, height: 196)
                Text(verbatim: "—")
                    .vaultType(.largeTitle)
                    .themedForeground(.tertiary)
            }
            // 270° gauge leaves a bottom gap; pull the caption up into it.
            .frame(height: 176, alignment: .top)

            Text("Not checked yet")
                .vaultType(.footnote)
                .themedForeground(.tertiary)
        }
    }
}
