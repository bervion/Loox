import XCTest
import UIKit
import CoreGraphics
@testable import Vaultify

/// Pure-logic coverage for the theme engine: settings codec, accent recolor,
/// auto-night resolution, legacy migration mapping, mesh math/renderer, and the
/// `.vaultheme` exchange codec. (Visual pieces are verified on device.)
final class ThemeEngineTests: XCTestCase {

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
        XCTAssertEqual(onWhiteAccent.switchOn, 0xFFFFFF)
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

    func testBuiltinAccentForegroundMeetsWCAGAA() {
        for theme in BuiltinTheme.allCases {
            let p = BuiltinThemes.palette(theme)
            let ratio = RGBMath.contrastRatio(p.accentForeground, p.accent)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(theme) on-accent contrast \(ratio) < AA")
        }
    }

    func testAccentPresetsGetReadableForeground() {
        for preset in AccentPreset.allCases {
            let t = BuiltinThemes.night.recolored(accent: preset.rgb)
            let ratio = RGBMath.contrastRatio(t.accentForeground, preset.rgb)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(preset) on-accent contrast \(ratio) < AA")
        }
    }

    func testAccentPresetRGB() {
        XCTAssertEqual(AccentPreset.blue.rgb, 0x2C6ECB)
        XCTAssertEqual(AppAccentColor(base: .red, customRGB: 0x123456).rgb, 0x123456)
        XCTAssertEqual(AppAccentColor(base: .red).rgb, AccentPreset.red.rgb)
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
        let settings = ThemeSettings.default   // theme=day, nightTheme=night, autoNight=system
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
        settings.accents["builtin.day"] = AppAccentColor(base: .red)
        XCTAssertEqual(ThemePalette.resolve(settings, systemIsDark: false, brightness: 1).accent, AccentPreset.red.rgb)
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
        let theme = CustomTheme(name: "Sunset", base: .nightTinted, accent: AppAccentColor(base: .orange),
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
