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
            // Disabled state uses an OPAQUE muted fill (blend toward background), never
            // `.opacity` — a translucent CTA lets content scrolling behind a pinned button
            // show through. Only the momentary pressed state dims.
            let bg = isEnabled ? theme.accent : RGBMath.blend(theme.accent, theme.background, 0.55)
            let fg = isEnabled ? theme.accentForeground : RGBMath.blend(theme.accentForeground, bg, 0.4)
            configuration.label
                .vaultType(.headline)
                .foregroundStyle(Color(rgb: fg))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
                .background(Color(rgb: bg))
                .vaultCornerRadius(Radius.sm)
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

/// Tinted (soft) button — accent text on a control surface.
struct ThemedTintedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { StyledButton(configuration: configuration) }

    private struct StyledButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(AppEnvironment.self) private var env
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            let theme = env.theme.active
            // Soft ACCENT fill, not a neutral control surface: on the grouped
            // sheet background a gray fill disappears entirely (same gray on
            // gray) — the tinted rank must still read as a button. The label is
            // TEXT rank: `accentText` clears 4.5:1 on the soft fill, where the
            // raw fill-tuned accent sits as low as 3.05:1 on some presets.
            let fg = isEnabled ? theme.accentText : theme.textDisabled
            configuration.label
                .vaultType(.headline)
                .foregroundStyle(Color(rgb: fg))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
                .background(Color(rgb: theme.accentSoft))
                .vaultCornerRadius(Radius.sm)
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
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            let theme = env.theme.active
            // Opaque muted fill when disabled (blend toward background), never `.opacity`.
            let bg = isEnabled ? theme.destructive : RGBMath.blend(theme.destructive, theme.background, 0.55)
            let fg = isEnabled ? RGBMath.onColor(theme.destructive) : RGBMath.blend(RGBMath.onColor(theme.destructive), bg, 0.4)
            configuration.label
                .vaultType(.headline)
                .foregroundStyle(Color(rgb: fg))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.s4)
                .background(Color(rgb: bg))
                .vaultCornerRadius(Radius.sm)
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}

/// Compact themed button, sized to its content instead of `maxWidth: .infinity` — for an inline
/// secondary action placed next to a row label (e.g. `LocatedInSheet`'s "Move" button beside the
/// current Space's folder badge, `NotificationsScreen`'s "Not Now"/"Accept" invite-row pair).
/// Shares `theme.accent`/`theme.controlBackground` semantics with `ThemedProminentButtonStyle` /
/// `ThemedTintedButtonStyle`; pick `.prominent` for the row's primary action, `.tinted` (default)
/// for the secondary one.
struct ThemedCompactButtonStyle: ButtonStyle {
    enum Emphasis {
        case tinted
        case prominent
    }

    var emphasis: Emphasis = .tinted

    func makeBody(configuration: Configuration) -> some View {
        StyledButton(emphasis: emphasis, configuration: configuration)
    }

    private struct StyledButton: View {
        let emphasis: Emphasis
        let configuration: ButtonStyleConfiguration
        @Environment(AppEnvironment.self) private var env
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            let (bg, fg) = fillAndForeground()
            configuration.label
                .vaultType(.subhead).fontWeight(.medium)
                .foregroundStyle(Color(rgb: fg))
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s2)
                .background(Color(rgb: bg))
                .vaultCornerRadius(Radius.sm)
                // The pill above stays visually compact; this floor only grows the
                // invisible hit region so short labels still clear the 44pt minimum.
                .frame(minHeight: Metric.hitMin)
                .contentShape(.rect)
                .opacity(configuration.isPressed ? 0.85 : 1)
        }

        // Plain (non-`@ViewBuilder`) function — a `switch` inline inside `body` gets
        // misparsed as a view-building switch by the ViewBuilder inference, so the
        // fill/foreground branch lives here instead.
        private func fillAndForeground() -> (bg: UInt32, fg: UInt32) {
            let theme = env.theme.active
            switch emphasis {
            case .prominent:
                let bg = isEnabled ? theme.accent : RGBMath.blend(theme.accent, theme.background, 0.55)
                let fg = isEnabled ? theme.accentForeground : RGBMath.blend(theme.accentForeground, bg, 0.4)
                return (bg, fg)
            case .tinted:
                // TEXT rank on a control fill — see ThemedTintedButtonStyle.
                return (theme.controlBackground, isEnabled ? theme.accentText : theme.textDisabled)
            }
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
extension ButtonStyle where Self == ThemedCompactButtonStyle {
    /// Secondary inline action (soft tint on `controlBackground`).
    static var themedCompact: ThemedCompactButtonStyle { .init() }
    /// Primary inline action (filled `accent`) for a compact row pair.
    static var themedCompactProminent: ThemedCompactButtonStyle { .init(emphasis: .prominent) }
}
