import SwiftUI

// MARK: - StrengthBar

/// Horizontal strength bar: a solid success fill on the left scaled to `value`%,
/// then a faded spectrum remainder — mirrors `StrengthBar` in Watchtower.jsx.
struct WatchtowerStrengthBar: View {
    /// 0-100 target strength.
    let value: Int

    @State private var shown: CGFloat = 0   // animates 0 → value on entry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Spectrum colours matching the DS StrengthBar definition (right → left fade)
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
                // Solid success fill portion — grows in from 0 on entry
                Capsule()
                    .fill(Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255))
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
    @State private var isPressed = false

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
            .background(
                isPressed
                    ? Color(rgb: theme.surfacePressed)
                    : Color(rgb: theme.elevatedBackground)
            )
            .animation(.timingCurve(0.32, 0.72, 0, 1, duration: Motion.fast), value: isPressed)
        }
        .buttonStyle(.plain)
        // Manual press state so we can replicate the DS pressed background swap
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color(rgb: theme.separator), lineWidth: 0.5)
        )
        .accessibilityLabel(Text("Overall password strength: \(overallStrength)%"))
        .accessibilityAddTraits(.isButton)
    }
}
