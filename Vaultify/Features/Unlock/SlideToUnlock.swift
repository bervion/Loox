import SwiftUI

/// A drag-to-confirm control: the user slides the knob to the end to confirm it's safe to
/// unlock. Used on the lock screen after a shake-lock so Face ID isn't prompted until the user
/// deliberately acts. Snaps back if released early.
struct SlideToUnlock: View {
    var label: LocalizedStringResource = "Slide to unlock"
    let onComplete: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var offsetX: CGFloat = 0
    @State private var completed = false

    private let height: CGFloat = Metric.rowHeight
    private let inset: CGFloat = Space.s1
    private var knob: CGFloat { height - inset * 2 }

    var body: some View {
        let theme = env.theme.active
        GeometryReader { geo in
            let maxX = max(geo.size.width - knob - inset * 2, 0)
            let progress = maxX > 0 ? offsetX / maxX : 0

            ZStack(alignment: .leading) {
                Capsule().fill(Color(rgb: theme.controlBackground))

                Text(label)
                    .vaultType(.subhead).fontWeight(.medium)
                    .themedForeground(.secondary)
                    .frame(maxWidth: .infinity)
                    .opacity(1 - progress * 1.4)

                // Sliding knob (accent fill + arrow — a deliberate action control).
                ZStack {
                    Circle().fill(Color(rgb: theme.accent))
                    PolarisIcon(Icons.arrowRight, size: 20)
                        .foregroundStyle(Color(rgb: theme.accentForeground))
                }
                .frame(width: knob, height: knob)
                .padding(inset)
                .offset(x: offsetX)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !completed else { return }
                            offsetX = min(max(0, value.translation.width), maxX)
                        }
                        .onEnded { _ in
                            guard !completed else { return }
                            if offsetX >= maxX * 0.9 {
                                completed = true
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offsetX = maxX }
                                Haptics.success()
                                onComplete()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offsetX = 0 }
                            }
                        }
                )
            }
        }
        .frame(height: height)
    }
}
