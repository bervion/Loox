import XCTest
import UIKit
import CoreGraphics
@testable import Vaultify

/// Pure-logic coverage for the theme engine: settings codec, accent recolor,
/// auto-night resolution, legacy migration mapping, mesh math/renderer, the
/// `.vaultheme` exchange codec, and the onboarding forced-light gate. (Visual
/// pieces are verified on device.) `@MainActor` because `ThemeStore`/`SettingsStore`
/// are main-actor isolated.
@MainActor
final class ThemeEngineTests: XCTestCase {

    override func tearDown() {
        // `ThemeStore`/`SettingsStore` construction below persists through
        // `ThemeReader`/`UserDefaults` (App Group when available, else `.standard`,
        // matching production) — reset so later tests never see a `forceLight`
        // or theme override written by a run of this suite.
        ThemeReader.save(.default)
        super.tearDown()
    }

    // MARK: Settings codec

    func testThemeSettingsCodableRoundTrip() throws {
        var settings = ThemeSettings.default
        settings.theme = .builtin(.nightTinted)
        settings.accents["builtin.night"] = AppAccentColor(base: .purple)
        settings.wallpapers["builtin.night"] = .gradient(
            colors: [0x112233, 0x445566],
            settings: WallpaperSettings(blur: true, dimAlpha: 0.2, intensity: 0.7, rotation: 45, motion: true))
        settings.customThemes = [CustomTheme(name: "Mine", base: .day, accent: AppAccentColor(base: .teal),
                                             wallpaper: .mesh(colors: [0x010203, 0x040506]))]
        settings.autoNight = .time(fromMinutes: 22 * 60, toMinutes: 7 * 60)
        settings.fontScale = .large

        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(ThemeSettings.self, from: data), settings)
    }

    func testWallpaperCasesCodable() throws {
        let cases: [Wallpaper] = [
            .none, .solid(0xABCDEF),
            .gradient(colors: [0x111111, 0x222222], settings: .none),
            .mesh(colors: [0x7FA381, 0xFFF5C5, 0x336F55, 0xFBE37D]),
            .pattern(id: "dots", colors: [0x000000], settings: WallpaperSettings(intensity: 0.3)),
            .image(fileName: "abc.jpg", settings: WallpaperSettings(blur: true)),
        ]
        for wallpaper in cases {
            let data = try JSONEncoder().encode(wallpaper)
            XCTAssertEqual(try JSONDecoder().decode(Wallpaper.self, from: data), wallpaper)
        }
    }

    // MARK: Accent recolor

    func testRecolorSetsAccentAndContrastForeground() {
        let onWhiteAccent = BuiltinThemes.night.recolored(accent: 0xFFFFFF)
        XCTAssertEqual(onWhiteAccent.accent, 0xFFFFFF)
        // The switch track guards against its own WHITE knob (Controlled
        // Contrast) — a white accent must NOT stay a white track.
        XCTAssertNotEqual(onWhiteAccent.switchOn, 0xFFFFFF)
        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(onWhiteAccent.switchOn, 0xFFFFFF), 2.0)
        XCTAssertEqual(onWhiteAccent.accentForeground, 0x000000)

        let onDarkAccent = BuiltinThemes.day.recolored(accent: 0x101010)
        XCTAssertEqual(onDarkAccent.accentForeground, 0xFFFFFF)
    }

    func testOnColorPicksHigherContrast() {
        XCTAssertEqual(RGBMath.onColor(0xFFFFFF), 0x000000)
        XCTAssertEqual(RGBMath.onColor(0x000000), 0xFFFFFF)
        // Night accent is light enough that dark text wins (was white → 2.79:1 before).
        XCTAssertEqual(RGBMath.onColor(0x5B9CF6), 0x000000)
    }

    // `accentForeground` is the foreground for tinted **controls** (buttons / badges) whose labels
    // are bold/large, so the applicable bar is WCAG AA for large text (3.0:1) — not 4.5:1. `onAccent`
    // deliberately prefers white above the 3.0 floor (iOS coloured-button convention); see
    // `RGBMath.onAccent`. (Small on-accent text, if any, should use a max-contrast token instead.)
    private let onAccentMinContrast = 3.0

    func testBuiltinAccentForegroundMeetsWCAGAA() {
        for theme in BuiltinTheme.allCases {
            let p = BuiltinThemes.palette(theme)
            let ratio = RGBMath.contrastRatio(p.accentForeground, p.accent)
            XCTAssertGreaterThanOrEqual(ratio, onAccentMinContrast, "\(theme) on-accent contrast \(ratio) < AA-large")
        }
    }

    func testAccentPresetsGetReadableForeground() {
        // On-accent must clear the large-text floor for all 7 presets in light AND dark.
        for preset in AccentPreset.allCases {
            for isDark in [false, true] {
                let base = isDark ? BuiltinThemes.night : BuiltinThemes.day
                let accent = preset.rgb(isDark: isDark)
                let t = base.recolored(accent: accent)
                // Measure against the GUARDED fill (t.accent): the contrast
                // pipeline may pull a bright brand hue to the 3:1 floor, and
                // the foreground is derived from that adjusted fill.
                let ratio = RGBMath.contrastRatio(t.accentForeground, t.accent)
                XCTAssertGreaterThanOrEqual(ratio, onAccentMinContrast, "\(preset) \(isDark ? "dark" : "light") on-accent contrast \(ratio) < AA-large")
            }
        }
    }

    func testAccentPresetRGB() {
        // The seven Design-System presets resolve light/dark hues from accents.css.
        XCTAssertEqual(AccentPreset.blue.rgb(isDark: false), 0x009DFF)
        XCTAssertEqual(AccentPreset.blue.rgb(isDark: true), 0x009DFF)
        XCTAssertEqual(AccentPreset.mono.rgb(isDark: false), 0x1C1C1E)
        XCTAssertEqual(AccentPreset.mono.rgb(isDark: true), 0xFFFFFF)
        // Custom RGB was removed: resolution ignores any legacy customRGB value.
        XCTAssertEqual(AppAccentColor(base: .teal, customRGB: 0x123456).rgb(isDark: false),
                       AccentPreset.teal.lightRGB)
    }

    func testAccentPresetTolerantDecodeOfRemovedCase() throws {
        // Older builds persisted cases that no longer exist (e.g. "orange") → fall back to blue.
        let decoded = try JSONDecoder().decode(AccentPreset.self, from: Data(#""orange""#.utf8))
        XCTAssertEqual(decoded, .blue)
    }

    // MARK: Auto-night

    func testAutoNightOffReturnsNil() {
        XCTAssertNil(AutoNight.prefersNight(.off, systemIsDark: true, brightness: 1))
    }

    func testAutoNightSystemFollowsTrait() {
        XCTAssertEqual(AutoNight.prefersNight(.system, systemIsDark: true, brightness: 1), true)
        XCTAssertEqual(AutoNight.prefersNight(.system, systemIsDark: false, brightness: 1), false)
    }

    func testAutoNightBrightnessThreshold() {
        XCTAssertEqual(AutoNight.prefersNight(.brightness(threshold: 0.5), systemIsDark: false, brightness: 0.3), true)
        XCTAssertEqual(AutoNight.prefersNight(.brightness(threshold: 0.5), systemIsDark: false, brightness: 0.8), false)
    }

    func testAutoNightTimeWindowCrossingMidnight() {
        func at(_ hour: Int, _ minute: Int) -> Date {
            Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
        }
        // 22:00 → 07:00 (crosses midnight)
        XCTAssertTrue(AutoNight.inWindow(now: at(23, 0), fromMinutes: 22 * 60, toMinutes: 7 * 60))
        XCTAssertTrue(AutoNight.inWindow(now: at(2, 0), fromMinutes: 22 * 60, toMinutes: 7 * 60))
        XCTAssertFalse(AutoNight.inWindow(now: at(12, 0), fromMinutes: 22 * 60, toMinutes: 7 * 60))
        // 09:00 → 17:00 (no crossing)
        XCTAssertTrue(AutoNight.inWindow(now: at(10, 0), fromMinutes: 9 * 60, toMinutes: 17 * 60))
        XCTAssertFalse(AutoNight.inWindow(now: at(18, 0), fromMinutes: 9 * 60, toMinutes: 17 * 60))
    }

    // MARK: Resolution

    func testResolvePicksDayOrNight() {
        // System-following resolution — set explicitly (the fresh-install
        // default is now light/auto-night OFF).
        var settings = ThemeSettings.default   // theme=day, nightTheme=night
        settings.autoNight = .system
        let dark = ThemePalette.resolve(settings, systemIsDark: true, brightness: 1)
        XCTAssertTrue(dark.isDark)
        XCTAssertEqual(dark.reference, .builtin(.night))

        let light = ThemePalette.resolve(settings, systemIsDark: false, brightness: 1)
        XCTAssertFalse(light.isDark)
        XCTAssertEqual(light.reference, .builtin(.day))
    }

    func testResolveAppliesAccentOverride() {
        var settings = ThemeSettings.default
        settings.theme = .builtin(.day)
        settings.autoNight = .off
        settings.accents["builtin.day"] = AppAccentColor(base: .pink)
        XCTAssertEqual(ThemePalette.resolve(settings, systemIsDark: false, brightness: 1).accent, AccentPreset.pink.rgb(isDark: false))
    }

    func testActiveWallpaperUsesBuiltinDefaults() {
        var settings = ThemeSettings.default
        settings.autoNight = .off

        // Day and Night stay clean (just the theme background).
        settings.theme = .builtin(.night)
        XCTAssertEqual(ThemePalette.activeWallpaper(settings, systemIsDark: false, brightness: 1), .none)
        settings.theme = .builtin(.day)
        XCTAssertEqual(ThemePalette.activeWallpaper(settings, systemIsDark: false, brightness: 1), .none)

        // Night Tinted ships a subtle gradient by default — being tinted is its point.
        settings.theme = .builtin(.nightTinted)
        if case .gradient = ThemePalette.activeWallpaper(settings, systemIsDark: false, brightness: 1) {
            // expected
        } else {
            XCTFail("night tinted should default to a gradient wallpaper")
        }
    }

    // MARK: Forced light (onboarding)

    /// Fresh state: `forceLight` pins the resolved palette, `preferredColorScheme`,
    /// `interfaceStyle`, and the legacy `appearanceMode` bridge to Light — regardless
    /// of whatever `ThemeSettings` happen to be persisted (day/night/system).
    func testForceLightPinsLightRegardlessOfSettings() {
        let store = ThemeStore(forceLight: true)
        XCTAssertFalse(store.active.isDark)
        XCTAssertEqual(store.preferredColorScheme, .light)
        XCTAssertEqual(store.interfaceStyle, .light)
        XCTAssertEqual(store.appearanceMode, .light)
    }

    /// Regression test for the welcome-carousel background→foreground flip: a
    /// reported system scheme change is recorded, but must not leak into the active
    /// palette while the onboarding forced-light gate is still up.
    func testForceLightIgnoresSystemColorSchemeChanges() {
        let store = ThemeStore(forceLight: true)
        store.systemColorSchemeChanged(.dark)
        XCTAssertTrue(store.systemIsDark, "the device scheme is still recorded")
        XCTAssertFalse(store.active.isDark, "but must not flip the active palette")
        XCTAssertEqual(store.preferredColorScheme, .light)
        XCTAssertEqual(store.interfaceStyle, .light)
    }

    /// After `markAppearanceChosen()`: a pick made while still forced applies live,
    /// and the gate never re-engages afterward.
    func testMarkAppearanceChosenAppliesPendingChoiceAndReleasesGate() {
        let store = ThemeStore(forceLight: true)
        store.appearanceMode = .dark
        // Still pinned light until the choice is confirmed.
        XCTAssertFalse(store.active.isDark)

        store.markAppearanceChosen()
        XCTAssertFalse(store.forceLight)
        XCTAssertTrue(store.active.isDark)
        XCTAssertEqual(store.preferredColorScheme, .dark)
        XCTAssertEqual(store.appearanceMode, .dark)

        // Idempotent: calling again (e.g. onboarding's completion safety net) is a no-op.
        store.markAppearanceChosen()
        XCTAssertFalse(store.forceLight)
        XCTAssertTrue(store.active.isDark)
    }

    /// Onboarded user, never forced: with the gate already released at construction
    /// (mirrors an already-onboarded `SettingsStore.hasChosenAppearance == true`),
    /// `appearanceMode` mutations apply exactly as before this fix — including
    /// following the device via `.system`.
    func testThemeStoreNotForcedRespectsAppearanceModeImmediately() {
        let store = ThemeStore(forceLight: false)
        store.appearanceMode = .dark
        XCTAssertTrue(store.active.isDark)
        XCTAssertEqual(store.preferredColorScheme, .dark)

        store.appearanceMode = .system
        XCTAssertEqual(store.appearanceMode, .system)
        XCTAssertNil(store.preferredColorScheme, "System mode must keep following the device")
    }

    /// `SettingsStore.hasChosenAppearance` back-compat: an already-onboarded install
    /// predates this flag (its key is absent), so it must back-fill to "already
    /// chosen" from `onboardingCompleted` — never force-light an existing user. A
    /// genuinely fresh install has `onboardingCompleted == false` too, so the same
    /// fallback correctly yields "not yet chosen" there.
    func testHasChosenAppearanceBackCompatDefaultsToOnboardingCompleted() {
        let defaults = UserDefaults.standard
        let savedOnboarding = defaults.object(forKey: "onboarding_completed")
        let savedChosen = defaults.object(forKey: "has_chosen_appearance")
        defer {
            if let savedOnboarding { defaults.set(savedOnboarding, forKey: "onboarding_completed") }
            else { defaults.removeObject(forKey: "onboarding_completed") }
            if let savedChosen { defaults.set(savedChosen, forKey: "has_chosen_appearance") }
            else { defaults.removeObject(forKey: "has_chosen_appearance") }
        }

        defaults.removeObject(forKey: "has_chosen_appearance")
        defaults.set(true, forKey: "onboarding_completed")
        XCTAssertTrue(SettingsStore().hasChosenAppearance, "already-onboarded install must never be forced")

        defaults.removeObject(forKey: "has_chosen_appearance")
        defaults.set(false, forKey: "onboarding_completed")
        XCTAssertFalse(SettingsStore().hasChosenAppearance, "fresh install has not chosen yet")
    }

    // MARK: Legacy migration mapping

    func testLegacyAppearanceMapping() {
        XCTAssertEqual(ThemeSettings.fromLegacyAppearance("light").theme, .builtin(.day))
        XCTAssertEqual(ThemeSettings.fromLegacyAppearance("light").autoNight, .off)
        XCTAssertEqual(ThemeSettings.fromLegacyAppearance("dark").theme, .builtin(.night))
        XCTAssertEqual(ThemeSettings.fromLegacyAppearance("system").autoNight, .system)
        XCTAssertEqual(ThemeSettings.fromLegacyAppearance("garbage").autoNight, .system)
    }

    // MARK: Mesh math

    func testShiftArrayRotatesLeft() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0)]
        XCTAssertEqual(MeshMath.shiftArray(points, offset: 1),
                       [CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 0, y: 0)])
        XCTAssertEqual(MeshMath.shiftArray(points, offset: 3), points)
    }

    func testMeshPositions() {
        XCTAssertEqual(MeshMath.gatherPositions(MeshMath.basePositions).count, 4)
        XCTAssertEqual(MeshMath.positions(phase: 2), MeshMath.positions(phase: 2))
        XCTAssertEqual(MeshMath.positions(phase: 0).count, 4)
    }

    func testInterpolateMidpoint() {
        let mid = MeshMath.interpolate(CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 2), at: 0.5)
        XCTAssertEqual(mid.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mid.y, 1.0, accuracy: 1e-9)
    }

    // MARK: Mesh renderer

    func testMeshRendererProducesImage() {
        let image = MeshGradientRenderer.image(
            size: 16,
            colors: [0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00],
            positions: MeshMath.positions(phase: 0))
        XCTAssertNotNil(image)
        XCTAssertEqual(image?.cgImage?.width, 16)
    }

    func testMeshRendererRejectsMismatchedCounts() {
        XCTAssertNil(MeshGradientRenderer.image(colors: [0xFF0000], positions: []))
    }

    // MARK: Theme exchange

    func testVaultThemeRoundTripAssignsFreshID() throws {
        let theme = CustomTheme(name: "Sunset", base: .nightTinted, accent: AppAccentColor(base: .pink),
                                wallpaper: .gradient(colors: [0x111111, 0x222222], settings: .none))
        let decoded = try ThemeExchange.decode(try ThemeExchange.encode(theme))
        XCTAssertEqual(decoded.name, theme.name)
        XCTAssertEqual(decoded.base, theme.base)
        XCTAssertEqual(decoded.accent, theme.accent)
        XCTAssertEqual(decoded.wallpaper, theme.wallpaper)
        XCTAssertNotEqual(decoded.id, theme.id)
    }

    func testVaultThemeRejectsFutureSchema() throws {
        let data = try ThemeExchange.encode(CustomTheme(name: "x", base: .day))
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["schema"] = 99
        let tampered = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try ThemeExchange.decode(tampered)) { error in
            XCTAssertTrue(error is ThemeExchange.ExchangeError)
        }
    }
}
