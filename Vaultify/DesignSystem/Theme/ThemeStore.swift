import SwiftUI
import UIKit

/// Observable, UI-facing wrapper over the shared theme core. Owns the live
/// `ThemeSettings`, resolves the active `AppTheme`, and persists changes to the App
/// Group. Pure/heavy work lives in `VaultifyCore` (`ThemePalette` / `ThemeReader`).
@MainActor @Observable final class ThemeStore {
    private(set) var settings: ThemeSettings
    private(set) var active: AppTheme

    /// Bumped to trigger a mesh-gradient morph (unlock / tab change). Wraps 0…7.
    private(set) var meshPhase = 0

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

    // MARK: - Mesh

    /// Advance the mesh phase → the animated mesh wallpaper morphs once.
    func morphMesh() { meshPhase = (meshPhase + 1) % 8 }

    // MARK: - Settings mutators

    func setTheme(_ ref: AppThemeReference) {
        update { settings in
            settings.theme = ref
            // A dark primary theme can't pair with auto-night's light↔dark switching, so
            // picking one switches to manual mode — keeps the rendered theme and the
            // forced color scheme in sync (avoids dark wallpaper + light system chrome).
            let picksDark: Bool
            switch ref {
            case .builtin(let builtin): picksDark = builtin.isDark
            case .custom(let id): picksDark = settings.customTheme(id)?.base.isDark ?? false
            }
            if picksDark { settings.autoNight = .off }
        }
    }
    func setNightTheme(_ ref: AppThemeReference) { update { $0.nightTheme = ref } }
    func setAutoNight(_ setting: AutoNightSetting) { update { $0.autoNight = setting } }
    func setFontScale(_ scale: FontScale) { update { $0.fontScale = scale } }
    func setReduceMotion(_ enabled: Bool) { update { $0.reduceMotion = enabled } }

    /// Set or clear (nil) the per-theme accent override.
    func setAccent(_ accent: AppAccentColor?, for ref: AppThemeReference) {
        update { $0.accents[ref.key] = accent }
    }

    /// Set or clear (nil → built-in default) the per-theme wallpaper.
    func setWallpaper(_ wallpaper: Wallpaper?, for ref: AppThemeReference) {
        update { $0.wallpapers[ref.key] = wallpaper }
    }

    func saveCustomTheme(_ theme: CustomTheme) {
        update { settings in
            if let index = settings.customThemes.firstIndex(where: { $0.id == theme.id }) {
                settings.customThemes[index] = theme
            } else {
                settings.customThemes.append(theme)
            }
        }
    }

    func deleteCustomTheme(_ id: UUID) {
        update { settings in
            settings.customThemes.removeAll { $0.id == id }
            if settings.theme == .custom(id) { settings.theme = .builtin(.day) }
            if settings.nightTheme == .custom(id) { settings.nightTheme = .builtin(.night) }
        }
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
