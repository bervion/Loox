import SwiftUI

// MARK: - StrengthBar

/// Horizontal strength bar, 1Password-style: two capsules with a small seam —
/// a solid success fill on the left scaled to `value`%, and a soft light-green
/// remainder track. The fill grows in sync with the score gauge's count-up.
struct WatchtowerStrengthBar: View {
    /// 0-100 target strength.
    let value: Int
    /// Data-context identity (see `WatchtowerIntroGate`): the grow-in plays once
    /// per key, not on every tab revisit. Empty = ungated (always grow on appear).
    var introKey: String = ""

    @State private var shown: CGFloat = 0   // animates 0 → value on entry
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Same vivid display green as the score gauge band (the `.success`
        // token is text-tuned and reads heavy here); the remainder is the same
        // hue at low opacity so it composites over light AND dark cards.
        let fill = Color(rgb: watchtowerGaugeGreen(env.theme.active))
        GeometryReader { geo in
            // No minimum while collapsed — the fill grows smoothly from nothing
            // instead of popping in at capsule width when the animation starts.
            let fillWidth = shown <= 0 ? 0 : max(14, geo.size.width * shown / 100)
            HStack(spacing: 3) {
                Capsule()
                    .fill(fill)
                    .frame(width: fillWidth)
                Capsule()
                    .fill(fill.opacity(0.30))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14)
        .onAppear {
            if introKey.isEmpty || WatchtowerIntroGate.bar != introKey {
                WatchtowerIntroGate.bar = introKey
                grow()
            } else {
                shown = CGFloat(value)   // same data context — no replay
            }
        }
        .onChange(of: introKey) { _, new in
            WatchtowerIntroGate.bar = new
            grow()
        }
        // Silent data drift: track the new value without the entry animation.
        .onChange(of: value) { _, new in shown = CGFloat(new) }
    }

    /// Grow the success fill from 0 → value (frame width animates reliably).
    /// Delay + duration line up with the score gauge's count-up phase so the
    /// bar fills while the number rolls, one coordinated moment.
    private func grow() {
        if reduceMotion { shown = CGFloat(value); return }
        shown = 0
        withAnimation(.timingCurve(0.45, 0, 0.2, 1, duration: 1.35).delay(0.58)) {
            shown = CGFloat(value)
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
    var introKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: Space.s2) {
                Text("Overall password strength")
                    .vaultType(.headline)
                    .themedForeground(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PolarisIcon(Icons.chevronRight, size: Metric.iconInline)
                    .themedForeground(.iconDisabled)
            }
            WatchtowerStrengthBar(value: overallStrength, introKey: introKey)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text("Overall password strength: \(overallStrength)%"))
    }
}
