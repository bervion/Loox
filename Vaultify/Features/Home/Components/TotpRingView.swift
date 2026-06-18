import SwiftUI

/// Circular countdown ring showing the remaining seconds in the current TOTP
/// period. Warns in orange when ≤ 5 s remain. Under Reduce Motion the ring is
/// replaced by a plain numeric countdown (no animation).
struct TotpRingView: View {
    /// 0.0 … 1.0 — fraction of the period remaining.
    let progress: Double
    /// Integer seconds left in the current period.
    let remaining: Int
    var size: CGFloat = 26

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppEnvironment.self) private var env

    private var isWarning: Bool { remaining <= 5 }

    private var tintColor: Color {
        isWarning
            ? env.theme.active.color(.warning)
            : env.theme.active.color(.accent)
    }

    var body: some View {
        if reduceMotion {
            // Plain numeric fallback — no ring, just the countdown digit.
            Text("\(remaining)")
                .font(.vaultCode(.caption2, weight: .semibold))
                .foregroundStyle(tintColor)
                .monospacedDigit()
                .frame(width: size, height: size)
        } else {
            ring
        }
    }

    private var ring: some View {
        let r = (size - 4) / 2
        let circumference = 2 * Double.pi * r
        let dashOffset = circumference * (1 - progress)

        return ZStack {
            // Track
            Circle()
                .stroke(
                    tintColor.opacity(0.15),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            // Progress arc — rotated so 12 o'clock is the start.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    tintColor,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // Smooth sweep every second.
                .animation(.linear(duration: 1), value: dashOffset)

            // Remaining seconds centred in the ring.
            Text("\(remaining)")
                .font(.vaultCode(.caption2, weight: .semibold))
                .foregroundStyle(tintColor)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
