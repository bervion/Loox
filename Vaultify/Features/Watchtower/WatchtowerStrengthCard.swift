import SwiftUI

// MARK: - StrengthBar

/// Horizontal strength bar, 1Password-style: the vault's grade DISTRIBUTION as
/// overlapping capsules. Strongest grade first; each capsule spans from the left
/// edge to its cumulative share and stacks UNDER the one before it, so only its
/// rounded right end shows past the previous segment — the layered 1P look, not
/// separated blocks. A vault of only strong passwords reads as deep green over
/// light green; weaker grades trail off amber → orange → red.
///
/// The whole stack is clipped to the bar's capsule. That is the overflow fix,
/// not a cosmetic: the old two-capsule HStack animated a fixed-width child
/// against an already-settled layout, and replaying the intro mid-flight
/// (fast tab switches) let the animated frame paint outside the card. Here no
/// layer can ever draw past the clip shape, whatever the animation state.
struct WatchtowerStrengthBar: View {
    /// Grade → item count from `VaultHealth.grades`.
    let grades: [PasswordGrade: Int]
    /// Data-context identity (see `WatchtowerIntroGate`): the grow-in plays once
    /// per key, not on every tab revisit. Empty = ungated (always grow on appear).
    var introKey: String = ""

    @State private var progress: CGFloat = 0   // animates 0 → 1 on entry
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Every present segment keeps at least this much visible past the previous
    /// one — a grade with 2 items out of 200 still reads as a sliver instead of
    /// vanishing (exact counts live one tap deeper, on the strength screen).
    private static let minSliver: CGFloat = 12
    private static let barHeight: CGFloat = 18
    /// Surface-colored gap between segments (the 1P separation seam).
    private static let seamWidth: CGFloat = 2

    /// (hue, cumulative fraction 0…1) from strongest to weakest, only for
    /// grades present in the vault.
    private var segments: [(hue: UInt32, cumulative: CGFloat)] {
        let theme = env.theme.active
        let present = PasswordGrade.allCases.reversed()   // excellent → veryWeak
            .compactMap { grade -> (PasswordGrade, Int)? in
                guard let count = grades[grade], count > 0 else { return nil }
                return (grade, count)
            }
        let total = CGFloat(present.reduce(0) { $0 + $1.1 })
        guard total > 0 else { return [] }
        var cumulative: CGFloat = 0
        return present.map { grade, count in
            cumulative += CGFloat(count) / total
            return (watchtowerGradeHue(grade, theme: theme), min(1, cumulative))
        }
    }

    var body: some View {
        let theme = env.theme.active
        let segments = segments
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                // Track: the gauge green at low opacity, matching the old
                // remainder so an empty/unanalyzed vault still shows a quiet bar.
                Capsule().fill(Color(rgb: watchtowerGaugeGreen(theme)).opacity(0.30))

                // Weakest first (bottom), strongest last (top): each later
                // capsule covers the one below up to its own cumulative edge.
                // The seam is a CARD-colored capsule painted UNDER the colour,
                // proud of it at the trailing cap only — a full-height crescent
                // gap where one segment ends over the next (the 1P white-gap
                // effect). Painted under, not stroked over: an inner stroke's
                // outer edge antialiases against the saturated capsule beneath,
                // which read as a grey shadow on the white card. The widest
                // (weakest) capsule ends at the bar's own edge and carries no
                // seam — there is nothing beneath it to separate from.
                ForEach(Array(segments.enumerated().reversed()), id: \.offset) { index, segment in
                    let seam = index < segments.count - 1 ? Self.seamWidth : 0
                    Capsule()
                        .fill(Color(rgb: theme.elevatedBackground))
                        .overlay {
                            Capsule().fill(Color(rgb: segment.hue))
                                .padding(.trailing, seam)
                        }
                        .frame(width: segmentWidth(segment.cumulative, index: index,
                                                   of: segments, in: width))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: Self.barHeight)
        .onAppear {
            if introKey.isEmpty || WatchtowerIntroGate.bar != introKey {
                WatchtowerIntroGate.bar = introKey
                grow()
            } else {
                progress = 1   // same data context — no replay
            }
        }
        .onChange(of: introKey) { _, new in
            WatchtowerIntroGate.bar = new
            grow()
        }
    }

    /// Pixel width of a segment's capsule: cumulative share of the bar, floored
    /// so it pokes at least `minSliver` past the segment above it, and scaled by
    /// the intro progress (every capsule grows together, proportions constant).
    private func segmentWidth(_ cumulative: CGFloat, index: Int,
                              of segments: [(hue: UInt32, cumulative: CGFloat)],
                              in width: CGFloat) -> CGFloat {
        let innerEdge = index == 0 ? 0 : segments[index - 1].cumulative * width
        let floored = max(cumulative * width, innerEdge + Self.minSliver, Self.barHeight)
        return min(floored, width) * progress
    }

    /// Grow every capsule from 0 → its share (clipped, so replay mid-flight is
    /// safe). Delay + duration line up with the score gauge's count-up phase so
    /// the bar fills while the number rolls, one coordinated moment.
    private func grow() {
        if reduceMotion { progress = 1; return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }
        withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 1.35).delay(0.58)) {
            progress = 1
        }
    }
}

// MARK: - WatchtowerStrengthCard

/// Card content for "Overall password strength" + a horizontal strength bar.
/// A plain LABEL by design: the host wraps it in a `NavigationLink` (a Button in
/// here would swallow the link's tap — the card used to do exactly that, with an
/// empty action, so tapping it did nothing).
struct WatchtowerStrengthCard: View {
    let overallStrength: Int
    /// Grade distribution feeding the bar's layered segments.
    var grades: [PasswordGrade: Int] = [:]
    var introKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Text("Overall Password Strength")
                    .vaultType(.headline)
                    .themedForeground(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VaultIcon(Icons.chevronRight, size: Metric.iconInline)
                    .themedForeground(.iconDisabled)
            }
            WatchtowerStrengthBar(grades: grades, introKey: introKey)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text("Overall password strength: \(overallStrength)%"))
    }
}
