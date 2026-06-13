import SwiftUI

/// Live one-time code value (recomputes every second), grouped `123 456`.
struct TOTPCodeView: View {
    let secret: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(TOTPGenerator.code(forStoredValue: secret, date: context.date).map(Self.format) ?? "Invalid secret")
                .font(.vaultMono(.body, weight: .medium))
        }
    }

    static func format(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<mid]) \(code[mid...])"
    }
}

/// Circular TOTP countdown.
struct CountdownRing: View {
    let remaining: Int
    let period: Int

    var body: some View {
        ZStack {
            Circle().stroke(Color(.systemGray5), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(remaining) / CGFloat(max(period, 1)))
                .stroke(remaining <= 5 ? VaultColors.strengthWeak : Color.accentColor,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(remaining)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .frame(width: 26, height: 26)
        .animation(.linear(duration: 0.5), value: remaining)
    }
}
