import SwiftUI

// MARK: - StrengthBar

/// Horizontal strength bar: a solid success fill on the left scaled to `value`%,
/// then a faded spectrum remainder — mirrors `StrengthBar` in Watchtower.jsx.
struct WatchtowerStrengthBar: View {
    /// 0-100 target strength.
    let value: Int

    @State private var shown: CGFloat = 0   // animates 0 → value on entry
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Fixed illustrative spectrum matching the DS StrengthBar definition (right → left
    // fade) — a full-scale legend, not a per-item semantic status, so it intentionally
    // does not shift with theme/accent (mirrors the reference design 1:1).
    private static let spectrum: [Color] = [
        Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255),
        Color(red: 0x65/255, green: 0xD4/255, blue: 0x3A/255),
        Color(red: 0xA3/255, green: 0xE6/255, blue: 0x35/255),
        Color(red: 0xFA/255, green: 0xCC/255, blue: 0x15/255),
        Color(red: 0xFB/255, green: 0xBF/255, blue: 0x24/255),
        Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255),
        Color(red: 0xF9/255, green: 0x73/255, blue: 0x16/255),
        Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255),
    ]

    var body: some View {
        GeometryReader { geo in
            let fillWidth = max(14, geo.size.width * shown / 100)
            HStack(spacing: Space.s1) {
                // Solid success fill portion — grows in from 0 on entry. Routed
                // through the theme's `.success` role (not a fixed hex) so it stays
                // WCAG-legible and on-brand across every accent preset + appearance.
                Capsule()
                    .fill(env.theme.active.color(.success))
                    .frame(width: fillWidth)

                // Remaining spectrum segments
                HStack(spacing: Space.s1) {
                    ForEach(Self.spectrum.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(Self.spectrum[i].opacity(0.9))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 14)
        .onAppear { grow() }
        .onChange(of: value) { _, _ in grow() }
    }

    /// Grow the success fill from 0 → value (frame width animates reliably).
    private func grow() {
        if reduceMotion { shown = CGFloat(value); return }
        shown = 0
        withAnimation(.easeOut(duration: Motion.slow * 3)) {   // ~0.96s, alongside the gauge
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
