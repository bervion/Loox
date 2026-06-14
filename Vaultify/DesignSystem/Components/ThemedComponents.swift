import SwiftUI

// Reusable, theme-driven building blocks. Components read the active theme from the
// shared @Observable `AppEnvironment` (`env.theme.active`), so they update live
// everywhere — including inside sheets, where a plain EnvironmentKey value can go stale.

// MARK: - Semantic text color

enum ThemeRole {
    case primary, secondary, tertiary, accent, destructive, success, warning, onAccent
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
        case .accent: return Color(rgb: accent)
        case .destructive: return Color(rgb: destructive)
        case .success: return Color(rgb: success)
        case .warning: return Color(rgb: warning)
        case .onAccent: return Color(rgb: accentForeground)
        }
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

private struct ThemedFormBackgroundModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
    }
}

// MARK: - Card

/// An elevated surface that floats over the background / wallpaper and stays legible.
struct ThemedCard<Content: View>: View {
    @Environment(AppEnvironment.self) private var env
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        let theme = env.theme.active
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: theme.elevatedBackground))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(rgb: theme.separator), lineWidth: 0.5))
    }
}

extension View {
    /// Wrap the receiver in a themed card surface.
    func themedCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
        ThemedCard(cornerRadius: cornerRadius, padding: padding) { self }
    }
}

// MARK: - Divider

struct ThemedDivider: View {
    @Environment(AppEnvironment.self) private var env
    var body: some View { Rectangle().fill(Color(rgb: env.theme.active.separator)).frame(height: 0.5) }
}
