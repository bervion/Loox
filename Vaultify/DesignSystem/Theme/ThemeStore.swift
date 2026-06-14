import SwiftUI
import UIKit

/// Observable, UI-facing wrapper over the shared theme core. Owns the live
/// `ThemeSettings`, resolves the active `AppTheme`, and persists changes to the App
/// Group. Pure/heavy work lives in `VaultifyCore` (`ThemePalette` / `ThemeReader`).
@MainActor @Observable final class ThemeStore {
    private(set) var settings: ThemeSettings
    private(set) var active: AppTheme

    /// True device appearance, fed by the root view's `colorScheme` (auto-night).
    var systemIsDark: Bool { didSet { if systemIsDark != oldValue { recompute() } } }

    /// Screen brightness drives the `.brightness` auto-night trigger. Wired live in
    /// Phase 05; a neutral default keeps the trigger inert until then.
    private var brightness: Double = 1.0

    init() {
        let loaded = ThemeReader.load()
        let dark = UITraitCollection.current.userInterfaceStyle == .dark
        self.settings = loaded
        self.systemIsDark = dark
        self.active = ThemePalette.resolve(loaded, systemIsDark: dark, brightness: 1.0)
    }

    /// The active wallpaper (rendered from Phase 03).
    var wallpaper: Wallpaper {
        ThemePalette.activeWallpaper(settings, systemIsDark: systemIsDark, brightness: brightness)
    }

    /// `preferredColorScheme` for the window. `nil` follows the system (so the real
    /// `colorScheme` flows back into `systemIsDark` for auto-night).
    var preferredColorScheme: ColorScheme? {
        switch settings.autoNight {
        case .system: return nil
        case .off, .time, .brightness: return active.isDark ? .dark : .light
        }
    }

    var accentColor: Color { Color(rgb: active.accent) }

    // MARK: - System input

    func systemColorSchemeChanged(_ scheme: ColorScheme) {
        systemIsDark = (scheme == .dark)
    }

    // MARK: - Mutation

    /// Mutate settings, persist, and re-resolve the active theme.
    func update(_ mutate: (inout ThemeSettings) -> Void) {
        var next = settings
        mutate(&next)
        guard next != settings else { return }
        settings = next
        ThemeReader.save(next)
        recompute()
    }

    private func recompute() {
        active = ThemePalette.resolve(settings, systemIsDark: systemIsDark, brightness: brightness)
    }

    // MARK: - Legacy bridge

    /// Bridges the existing system/light/dark picker (onboarding + settings) onto the
    /// new model until the full Appearance UI lands in Phase 05.
    var appearanceMode: AppearanceMode {
        get {
            switch settings.autoNight {
            case .system: return .system
            default: return active.isDark ? .dark : .light
            }
        }
        set {
            update { settings in
                switch newValue {
                case .system:
                    settings.theme = .builtin(.day)
                    settings.nightTheme = .builtin(.night)
                    settings.autoNight = .system
                case .light:
                    settings.theme = .builtin(.day)
                    settings.autoNight = .off
                case .dark:
                    settings.theme = .builtin(.night)
                    settings.autoNight = .off
                }
            }
        }
    }
}
