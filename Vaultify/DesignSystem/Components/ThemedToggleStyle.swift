import SwiftUI

/// Theme-driven switch. Native `Toggle` derives its on-color from the environment
/// `tint` / app accent asset, which does not reliably reach toggles inside sheets +
/// `Form` (they fall back to an undefined tint → an all-white, unreadable switch in
/// dark mode). Drawing the track/knob ourselves from the active theme guarantees the
/// on/off colors are always correct, in every theme and color scheme. The `Toggle`
/// keeps its switch semantics/accessibility — only the visuals are customized.
struct ThemedToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { Switch(configuration: configuration) }

    private struct Switch: View {
        let configuration: Configuration
        @Environment(AppEnvironment.self) private var env
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        // Native UISwitch metrics so the control reads as a standard iOS switch.
        private let trackWidth: CGFloat = 51
        private let trackHeight: CGFloat = 31
        private let knob: CGFloat = 27

        var body: some View {
            let theme = env.theme.active
            HStack {
                configuration.label
                Spacer(minLength: 8)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(Color(rgb: configuration.isOn ? theme.switchOn : theme.controlBackground))
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                        .frame(width: knob, height: knob)
                        .padding(2)
                }
                .frame(width: trackWidth, height: trackHeight)
                .opacity(isEnabled ? 1 : 0.5)
                // Token spring, and nil under Reduce Motion so the knob swaps instantly.
                // This style is applied app-wide, so it is every switch in the app.
                .animation(.vault(Motion.spring, reduceMotion: reduceMotion), value: configuration.isOn)
            }
            .contentShape(.rect)
            .onTapGesture { if isEnabled { configuration.isOn.toggle() } }
        }
    }
}

extension ToggleStyle where Self == ThemedToggleStyle {
    static var themed: ThemedToggleStyle { .init() }
}
