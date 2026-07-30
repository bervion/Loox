import SwiftUI

// Reusable, theme-driven building blocks. Components read the active theme from the
// shared @Observable `AppEnvironment` (`env.theme.active`), so they update live
// everywhere — including inside sheets, where a plain EnvironmentKey value can go stale.

// MARK: - Semantic text color

enum ThemeRole {
    // Text
    case primary, secondary, tertiary, disabled
    // Icons (Design System icon roles)
    case iconPrimary, iconSecondary, iconDisabled
    // Accent + status. `accent` is the raw brand hue (icons, rings, strokes);
    // `accentFill` is what a FILLED control paints so its `onAccent` label
    // reads white; `accentText` is the same hue guarded to 4.5:1 on tinted
    // surfaces (links, tinted-button labels).
    case accent, accentFill, accentText, accentSoft, onAccent
    case destructive, onDestructive, success, warning
}

extension RotationTone {
    /// The theme role a rotation / attention tone paints with. `RotationTone` is
    /// pure core logic and knows nothing about themes; this is the single place the
    /// two vocabularies meet, so every surface showing a tone agrees on its color.
    var role: ThemeRole {
        switch self {
        case .destructive: return .destructive
        case .warning: return .warning
        case .neutral: return .secondary
        }
    }
}

extension View {
    /// Apply a semantic foreground color from the active theme.
    func themedForeground(_ role: ThemeRole = .primary) -> some View {
        modifier(ThemedForegroundModifier(role: role))
    }
}

private struct ThemedForegroundModifier: ViewModifier {
    let role: ThemeRole
    @Environment(AppEnvironment.self) private var env
    func body(content: Content) -> some View {
        content.foregroundStyle(env.theme.active.color(role))
    }
}

extension AppTheme {
    func color(_ role: ThemeRole) -> Color {
        switch role {
        case .primary: return Color(rgb: primaryText)
        case .secondary: return Color(rgb: secondaryText)
        case .tertiary: return Color(rgb: tertiaryText)
        case .disabled: return Color(rgb: textDisabled)
        case .iconPrimary: return Color(rgb: iconPrimary)
        case .iconSecondary: return Color(rgb: iconSecondary)
        case .iconDisabled: return Color(rgb: iconDisabled)
        case .accent: return Color(rgb: accent)
        case .accentFill: return Color(rgb: accentFill)
        case .accentText: return Color(rgb: accentText)
        case .accentSoft: return Color(rgb: accentSoft)
        case .onAccent: return Color(rgb: accentForeground)
        case .destructive: return Color(rgb: destructive)
        case .onDestructive: return Color(rgb: onDestructive)
        case .success: return Color(rgb: success)
        case .warning: return Color(rgb: warning)
        }
    }
}

// MARK: - Color scheme

extension View {
    /// Force this view's UIKit trait (navigation-bar title, `Form` section headers /
    /// footers, pickers, menus) to the active theme's light/dark. Sheets and
    /// full-screen covers do NOT inherit the root `.preferredColorScheme`, so their
    /// system chrome otherwise follows the *device* appearance — a light theme on a
    /// dark device renders an invisible light title on a light surface. Apply at every
    /// presented root (the preference propagates up to the sheet's hosting controller
    /// and down to pushed children).
    func themedColorScheme() -> some View { modifier(ThemedColorSchemeModifier()) }
}

private struct ThemedColorSchemeModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    func body(content: Content) -> some View {
        content.preferredColorScheme(env.theme.active.isDark ? .dark : .light)
    }
}

// MARK: - Background

extension View {
    /// Fill the screen with the theme's base background (settings / detail screens —
    /// the canvas screens use `.themedWallpaper` instead).
    func appBackground() -> some View { modifier(AppBackgroundModifier()) }
}

private struct AppBackgroundModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    func body(content: Content) -> some View {
        content.background(Color(rgb: env.theme.active.background).ignoresSafeArea())
    }
}

extension View {
    /// Themed backdrop for Form / List screens (non-canvas): hides the system scroll
    /// background and fills with the theme's grouped background, so tinted / custom
    /// themes show through while grouped cells stay legible.
    func themedFormBackground() -> some View { modifier(ThemedFormBackgroundModifier()) }
}

/// Which theme token backs a themed form/list surface. `.grouped` (default) is the
/// iOS-style gray canvas behind white cards; `.plain` uses the base background —
/// the Mac shell's list/detail columns set it so they read as white canvas
/// (password-manager idiom) while Settings keeps the grouped look.
enum ThemedSurfaceStyle { case grouped, plain }

private struct ThemedSurfaceStyleKey: EnvironmentKey {
    static let defaultValue = ThemedSurfaceStyle.grouped
}

extension EnvironmentValues {
    var themedSurfaceStyle: ThemedSurfaceStyle {
        get { self[ThemedSurfaceStyleKey.self] }
        set { self[ThemedSurfaceStyleKey.self] = newValue }
    }
}

private struct ThemedFormBackgroundModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.themedSurfaceStyle) private var surfaceStyle

    private var backdrop: UInt32 {
        surfaceStyle == .plain ? env.theme.active.background : env.theme.active.groupedBackground
    }

    func body(content: Content) -> some View {
        content
            // macOS's DEFAULT form style is "columns": the form hugs its content and
            // floats centred in the column, so the themed background became a gray
            // slab in a white void. Grouped matches iOS's default (full-height list)
            // on both platforms — set it here so every themed form gets it.
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Color(rgb: backdrop).ignoresSafeArea())
    }
}

// MARK: - Card

/// A grouped card surface — the iOS inset-grouped idiom. It reads as a card
/// purely from the fill contrast against the grouped page background (present it
/// on `themedFormBackground` / `groupedBackground`), with no hairline stroke.
struct ThemedCard<Content: View>: View {
    @Environment(AppEnvironment.self) private var env
    // DS scale: `Radius.md` (14) is the grouped-card tier.
    var cornerRadius: CGFloat = Radius.md
    var padding: CGFloat = Space.s4
    @ViewBuilder var content: Content

    var body: some View {
        let theme = env.theme.active
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: theme.elevatedBackground))
            .vaultCornerRadius(cornerRadius)
    }
}

extension View {
    /// Wrap the receiver in a themed card surface.
    func themedCard(cornerRadius: CGFloat = Radius.md, padding: CGFloat = Space.s4) -> some View {
        ThemedCard(cornerRadius: cornerRadius, padding: padding) { self }
    }
}

// MARK: - Divider

struct ThemedDivider: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View { Rectangle().fill(Color(rgb: env.theme.active.separator)).frame(height: 0.5) }
}
