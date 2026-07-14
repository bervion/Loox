import SwiftUI

/// First-launch Security surface: when the active persona has no items there is
/// nothing to score, so the misleading "At risk" ring and 100% strength bar are
/// replaced by one inviting card — the looping brand swirl (same mark as the QR
/// pairing screen), a short line, and a single CTA into the item editor.
struct WatchtowerEmptyStateCard: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: Space.s5) {
            // Continuous brand loop — the vault is idle, waiting for its first secret.
            LooxSwirlAnimationView(mode: .loop)
                .frame(width: 132, height: 132)

            VStack(spacing: Space.s2) {
                Text("Nothing to protect yet")
                    .vaultType(.headline)
                    .themedForeground(.primary)
                Text("Add your first password and Loox starts watching over your vault's security.")
                    .vaultType(.subhead)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onAdd) {
                HStack(spacing: Space.s2) {
                    PolarisIcon(Icons.pageAdd, size: Metric.iconInline)
                    Text("Add your first password")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity)
        .themedCard()
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
