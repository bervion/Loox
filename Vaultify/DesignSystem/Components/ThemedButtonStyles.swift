import SwiftUI

// Theme-driven button styles. Use `.buttonStyle(.themedProminent)` etc. so buttons
// across the app track the active theme's accent / surfaces automatically.

/// Filled accent button (primary call-to-action).
struct ThemedProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(AppEnvironment.self) private var env
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            let theme = env.theme.active
            configuration.label
                .font(.headline)
                .foregroundStyle(Color(rgb: theme.accentForeground))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(rgb: theme.accent))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
        }
    }
}

/// Tinted (soft) button — accent text on a control surface.
struct ThemedTintedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(AppEnvironment.self) private var env
        var body: some View {
            let theme = env.theme.active
            configuration.label
                .font(.headline)
                .foregroundStyle(Color(rgb: theme.accent))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(rgb: theme.controlBackground))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

/// Destructive (red) filled button.
struct ThemedDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(AppEnvironment.self) private var env
        var body: some View {
            let theme = env.theme.active
            configuration.label
                .font(.headline)
                .foregroundStyle(Color(rgb: RGBMath.onColor(theme.destructive)))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(rgb: theme.destructive))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

/// Shows a spinner over a button label while loading **without** changing the
/// label's size — the label stays laid out (just hidden) so the button keeps its
/// height and the tap doesn't make the control flick/resize. Spinner tint tracks
/// the prominent button's accent-foreground so it stays legible on the fill.
private struct ProminentButtonLoading: ViewModifier {
    let isLoading: Bool
    @Environment(AppEnvironment.self) private var env
    func body(content: Content) -> some View {
        content
            .opacity(isLoading ? 0 : 1)
            .overlay { if isLoading { ProgressView().tint(Color(rgb: env.theme.active.accentForeground)) } }
    }
}

extension View {
    /// Hide a prominent button's label and overlay a spinner while `isLoading`,
    /// preserving the button height (no resize flick on tap).
    func prominentButtonLoading(_ isLoading: Bool) -> some View {
        modifier(ProminentButtonLoading(isLoading: isLoading))
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
