import SwiftUI

// MARK: - StrengthBar

/// Horizontal strength bar, 1Password-style: two capsules with a small seam —
/// a solid success fill on the left scaled to `value`%, and a soft light-green
/// remainder track. The fill grows in sync with the score gauge's count-up.
struct WatchtowerStrengthBar: View {
    /// 0-100 target strength.
    let value: Int

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
        .onAppear { grow() }
        .onChange(of: value) { _, _ in grow() }
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

/// Tappable card showing "Overall password strength" + a horizontal strength bar.
/// Mirrors `StrengthCard` in Watchtower.jsx.
struct WatchtowerStrengthCard: View {
    let overallStrength: Int
    let onTap: () -> Void

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let theme = env.theme.active
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s2) {
                    Text("Overall password strength")
                        .vaultType(.headline)
                        .themedForeground(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PolarisIcon(Icons.chevronRight, size: Metric.iconInline)
                        .themedForeground(.iconDisabled)
                }
                WatchtowerStrengthBar(value: overallStrength)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // ButtonStyle press state (scroll-friendly — a minimumDistance:0 DragGesture
        // would block scrolling when a press lands on the card).
        .buttonStyle(PressableSurfaceStyle(theme: theme,
                                           base: Color(rgb: theme.elevatedBackground),
                                           cornerRadius: Radius.lg, bordered: true))
        .accessibilityLabel(Text("Overall password strength: \(overallStrength)%"))
        .accessibilityAddTraits(.isButton)
    }
}
