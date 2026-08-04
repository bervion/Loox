import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Observable, UI-facing wrapper over the shared theme core. Owns the live
/// `ThemeSettings`, resolves the active `AppTheme`, and persists changes to the App
/// Group. Pure/heavy work lives in `VaultifyCore` (`ThemePalette` / `ThemeReader`).
@MainActor @Observable final class ThemeStore {
    @ObservationIgnored private let persistChanges: Bool
    private(set) var settings: ThemeSettings
    private(set) var active: AppTheme

    /// Bumped to trigger a mesh-gradient morph (unlock / tab change). Wraps 0…7.
    private(set) var meshPhase = 0

    /// True device appearance, fed by the root view's `colorScheme` (auto-night).
    var systemIsDark: Bool { didSet { if systemIsDark != oldValue { recompute() } } }

    /// Screen brightness drives the `.brightness` auto-night trigger. Wired live in
    /// Phase 05; a neutral default keeps the trigger inert until then.
    private var brightness: Double = 1.0

    /// True until the user makes an explicit appearance choice (onboarding's
    /// ChooseTheme step) or onboarding completes without one (e.g. restoring an
    /// existing vault, which skips that step). While true, the resolved palette,
    /// `preferredColorScheme`, and `interfaceStyle` are pinned to LIGHT regardless of
    /// `appearanceMode` / the device scheme — first-run screens (splash, welcome,
    /// capability carousel) render predictably and never flip dark on a
    /// background→foreground during that window. Mirrors
    /// `SettingsStore.hasChosenAppearance`, which owns persistence; released via
    /// `markAppearanceChosen()`.
    private(set) var forceLight: Bool

    init(
        forceLight: Bool,
        settingsOverride: ThemeSettings? = nil,
        systemIsDarkOverride: Bool? = nil,
        persistChanges: Bool = true
    ) {
        self.persistChanges = persistChanges
        var loaded = settingsOverride ?? ThemeReader.load()
        // Sanitize an invalid persisted combo: auto-night switches primary↔night by
        // light/dark, so the primary must be a LIGHT theme. A dark primary + auto-night
        // renders dark while the window color scheme follows the device → mismatched
        // (light-mode) system chrome on a dark theme. Make such a combo manual.
        if settingsOverride == nil,
           loaded.autoNight != .off,
           Self.isDark(loaded.theme, in: loaded) {
            loaded.autoNight = .off
            ThemeReader.save(loaded)
        }
        #if canImport(UIKit)
        let detectedDark = UITraitCollection.current.userInterfaceStyle == .dark
        #elseif canImport(AppKit)
        let detectedDark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        #endif
        let dark = systemIsDarkOverride ?? detectedDark
        self.settings = loaded
        self.systemIsDark = dark
        self.forceLight = forceLight
        self.active = forceLight ? BuiltinThemes.day : ThemePalette.resolve(loaded, systemIsDark: dark, brightness: 1.0)
        ThemeHolder.current = self.active
    }

    /// Whether a theme reference resolves to a dark appearance.
    static func isDark(_ ref: AppThemeReference, in settings: ThemeSettings) -> Bool {
        switch ref {
        case .builtin(let builtin): return builtin.isDark
        case .custom(let id): return settings.customTheme(id)?.base.isDark ?? false
        }
    }

    /// The active wallpaper (rendered from Phase 03).
    var wallpaper: Wallpaper {
        ThemePalette.activeWallpaper(settings, systemIsDark: systemIsDark, brightness: brightness)
    }

    /// `preferredColorScheme` for the window. `nil` follows the system (so the real
    /// `colorScheme` flows back into `systemIsDark` for auto-night). Pinned to
    /// `.light` while `forceLight` — see that property.
    var preferredColorScheme: ColorScheme? {
        if forceLight { return .light }
        switch settings.autoNight {
        case .system: return nil
        case .off, .time, .brightness: return active.isDark ? .dark : .light
        }
    }

    var accentColor: Color { Color(rgb: active.accent) }

    /// App-wide control tint (drives `Color.accentColor`): the accent in light mode, but a
    /// neutral white in dark mode — the accent blue is low-contrast on dark glass / grey
    /// surfaces, whereas white reads cleanly. Filled accents and toggles keep the true accent
    /// explicitly (toggles via `.tint(VaultColors.accent)`).
    // TEXT rank: uiTint colors text buttons (Edit, nav actions) on card
    // surfaces, so light mode uses the contrast-guarded accentText.
    var uiTint: Color { Color(rgb: active.isDark ? active.primaryText : active.accentText) }

    /// Cross-platform interface style for the whole app — incl. presented sheets, which a
    /// SwiftUI `.preferredColorScheme` on the root does NOT reliably reach (so a sheet
    /// can stay dark on a light theme → invisible system text + dark sheet background).
    var interfaceStyle: PlatformAppearance.Style {
        if forceLight { return .light }
        switch settings.autoNight {
        case .system: return .unspecified
        case .off, .time, .brightness: return active.isDark ? .dark : .light
        }
    }

    /// Force every window (iOS) / the whole app (macOS) to the theme's light/dark, so
    /// sheets and the system chrome match the rendered theme. Called on theme change +
    /// on appear.
    func applyInterfaceStyle() {
        PlatformAppearance.forceInterfaceStyle(interfaceStyle)
    }

    // MARK: - System input

    /// True device appearance, reported by the root view on every scheme change
    /// (foreground, background→foreground, or a live device toggle). Recorded
    /// unconditionally — even while `forceLight` — but `recompute()` keeps serving
    /// the light palette until the gate releases, so this alone can never flip the
    /// active theme dark during the forced-light window.
    func systemColorSchemeChanged(_ scheme: ColorScheme) {
        systemIsDark = (scheme == .dark)
    }

    /// Releases the fresh-install forced-light gate (see `forceLight`): the user made
    /// an explicit appearance choice, or onboarding completed without one (e.g.
    /// restoring an existing vault, which skips the ChooseTheme step). Idempotent;
    /// re-resolves the active palette immediately so the release is live.
    func markAppearanceChosen() {
        guard forceLight else { return }
        forceLight = false
        recompute()
    }

    // MARK: - Mutation

    /// Mutate settings, persist, and re-resolve the active theme.
    func update(_ mutate: (inout ThemeSettings) -> Void) {
        var next = settings
        mutate(&next)
        guard next != settings else { return }
        settings = next
        if persistChanges {
            ThemeReader.save(next)
        }
        recompute()
    }

    private func recompute() {
        active = forceLight ? BuiltinThemes.day
            : ThemePalette.resolve(settings, systemIsDark: systemIsDark, brightness: brightness)
        ThemeHolder.current = active
        applyInterfaceStyle()
    }

    // MARK: - Mesh

    /// Advance the mesh phase → the animated mesh wallpaper morphs once.
    func morphMesh() { meshPhase = (meshPhase + 1) % 8 }

    // MARK: - Settings mutators

    func setTheme(_ ref: AppThemeReference) {
        // Builtin identifiers only; a custom theme id is meaningless (and
        // high-cardinality) off-device, so it reports as "custom".
        if case .builtin(let builtin) = ref {
            AnalyticsEngine.shared.log(.themeChanged(builtin.rawValue))
        } else {
            AnalyticsEngine.shared.log(.themeChanged("custom"))
        }
        update { settings in
            settings.theme = ref
            // Switching a theme resets it to its own defaults: drop any saved accent /
            // wallpaper customization for this theme so it always looks as designed (no
            // carried-over history from a previous customization).
            settings.accents[ref.key] = nil
            settings.wallpapers[ref.key] = nil
            // A dark primary can't pair with auto-night's light↔dark switch → make it
            // manual so the rendered theme and the forced color scheme stay in sync.
            if Self.isDark(ref, in: settings) { settings.autoNight = .off }
        }
    }
    func setNightTheme(_ ref: AppThemeReference) { update { $0.nightTheme = ref } }
    func setAutoNight(_ setting: AutoNightSetting) {
        update { settings in
            settings.autoNight = setting
            // Auto-night needs a light primary (it switches to the night theme itself).
            if setting != .off, Self.isDark(settings.theme, in: settings) {
                settings.theme = .builtin(.day)
            }
        }
    }
    func setFontScale(_ scale: FontScale) { update { $0.fontScale = scale } }

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
            // While forced, report Light — what onboarding is actually showing right
            // now — rather than the (possibly System/Dark) underlying settings, so
            // the ChooseTheme picker highlights the option the user is looking at.
            if forceLight { return .light }
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
