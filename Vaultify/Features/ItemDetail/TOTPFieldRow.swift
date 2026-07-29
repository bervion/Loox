import SwiftUI

/// Live one-time code value (recomputes every second), grouped `123 456`.
struct TOTPCodeView: View {
    let secret: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(TOTPGenerator.code(forStoredValue: secret, date: context.date).map(Self.format) ?? "Invalid secret")
                // SF, not MonoLisa: the code is a figure to read and retype, and SF's
                // digits are the more legible pair at a glance. `monospacedDigit` keeps
                // the width fixed so the number does not jitter as it ticks over.
                .vaultType(.section)
                .monospacedDigit()
                .lineLimit(1)
                // Guards against clipping at accessibility XXL Dynamic Type sizes
                // (title3 scales aggressively; the "123 456" grouping must survive).
                .minimumScaleFactor(0.7)
        }
    }

    nonisolated static func format(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<mid]) \(code[mid...])"
    }
}

/// Circular TOTP countdown.
struct CountdownRing: View {
    let remaining: Int
    let period: Int
    /// When drawn over the accent "copied" flash, switch to on-accent colours so the ring
    /// stays visible instead of blending into the accent background.
    var onAccent: Bool = false
    @Environment(AppEnvironment.self) private var env

    private var trackColor: Color {
        onAccent ? env.theme.active.color(.onAccent).opacity(0.3) : Color.platformSystemGray5
    }
    private var progressColor: Color {
        if onAccent { return env.theme.active.color(.onAccent) }
        if remaining <= 5 { return VaultColors.strengthWeak }     // red — about to expire
        if remaining <= 10 { return VaultColors.strengthMedium }  // yellow — running low
        return env.theme.active.color(.accent)                    // plenty of time, live theme accent
    }
    private var textColor: Color {
        onAccent ? env.theme.active.color(.onAccent) : env.theme.active.color(.secondary)
    }

    var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: CGFloat(remaining) / CGFloat(max(period, 1)))
                .stroke(progressColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(remaining)").vaultType(.caption).monospacedDigit().foregroundStyle(textColor)
        }
        .frame(width: 26, height: 26)
        .animation(.linear(duration: 0.5), value: remaining)
    }
}
