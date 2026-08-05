import SwiftUI

/// Beat 6's commitment control: BrandCapsuleCTA's visual language with a
/// hold-to-seal interaction — pressing sweeps a progress fill across the
/// capsule for 0.9s; release early and it lets go, hold through and the vault
/// seals under the user's own hand (the story's single haptic fires there).
///
/// VoiceOver and Switch Control get a plain button via
/// `accessibilityRepresentation` — a timed hold is never the only path. A
/// scene interruption mid-hold (banner, app switch) cancels the press so
/// returning cannot instantly complete the seal.
struct StorySealCTA: View {
    var title: LocalizedStringKey
    let onSealed: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var pressStart: Date?
    @State private var holdTask: Task<Void, Never>?
    @State private var sealed = false

    private static let holdDuration: TimeInterval = 0.9

    var body: some View {
        capsule
            .frame(height: Metric.controlLarge)
            .scaleEffect(pressStart == nil ? 1 : Motion.pressScale)
            .animation(Motion.spring, value: pressStart == nil)
            .gesture(holdGesture)
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { cancelHold() }
            }
            .accessibilityRepresentation {
                Button(title) { seal() }
            }
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s4)
            .vaultContentWidth(.form)
    }

    private var capsule: some View {
        ZStack {
            Capsule().fill(Color(rgb: theme.accentFill))
            GeometryReader { geo in
                TimelineView(.animation(paused: pressStart == nil)) { context in
                    Capsule()
                        .fill(Color(rgb: theme.accentForeground).opacity(0.22))
                        .frame(width: geo.size.width * fraction(at: context.date))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .clipShape(Capsule())
            .allowsHitTesting(false)
            Text(title)
                .vaultType(.body).fontWeight(.medium)
                .foregroundStyle(Color(rgb: theme.accentForeground))
        }
    }

    /// Sweep fill 0…1 while pressing; snaps back on release (the spring on the
    /// capsule scale carries the "let go" feel).
    private func fraction(at date: Date) -> CGFloat {
        guard let start = pressStart else { return 0 }
        return min(max(date.timeIntervalSince(start) / Self.holdDuration, 0), 1)
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard pressStart == nil, !sealed else { return }
                pressStart = Date()
                holdTask = Task {
                    try? await Task.sleep(for: .milliseconds(Int(Self.holdDuration * 1000)))
                    guard !Task.isCancelled else { return }
                    seal()
                }
            }
            .onEnded { _ in cancelHold() }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        pressStart = nil
    }

    private func seal() {
        guard !sealed else { return }
        sealed = true
        cancelHold()
        // The story's ONLY haptic: one selection tap at the commitment, per
        // the haptics vocabulary (success stays reserved for copy actions).
        Haptics.tap()
        onSealed()
    }
}
