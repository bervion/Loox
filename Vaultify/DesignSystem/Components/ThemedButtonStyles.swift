import SwiftUI

// Theme-driven button styles. Use `.buttonStyle(.themedProminent)` etc. so buttons
// across the app track the active theme's accent / surfaces automatically.

/// Filled accent button (primary call-to-action).
struct ThemedProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.appTheme) private var theme
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(Color(rgb: theme.accentForeground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(rgb: theme.accent))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
        }
    }
}

/// Tinted (soft) button — accent text on a control surface.
struct ThemedTintedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.appTheme) private var theme
        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(Color(rgb: theme.accent))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(rgb: theme.controlBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

/// Destructive (red) filled button.
struct ThemedDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.appTheme) private var theme
        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(rgb: theme.destructive))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

extension ButtonStyle where Self == ThemedProminentButtonStyle {
    static var themedProminent: ThemedProminentButtonStyle { .init() }
}
extension ButtonStyle where Self == ThemedTintedButtonStyle {
    static var themedTinted: ThemedTintedButtonStyle { .init() }
}
extension ButtonStyle where Self == ThemedDestructiveButtonStyle {
    static var themedDestructive: ThemedDestructiveButtonStyle { .init() }
}
