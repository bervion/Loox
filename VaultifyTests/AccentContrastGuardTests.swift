import XCTest
@testable import Vaultify

/// Controlled Contrast contract: the guard is non-destructive for passing
/// colors, every preset × builtin theme clears the WCAG floors on every
/// accent rank, and extreme inputs (black on black) stay visible instead of
/// sinking. This matrix is the regression gate for any future palette retune.
final class AccentContrastGuardTests: XCTestCase {

    private let themes: [(String, AppTheme)] = [
        ("day", BuiltinThemes.day),
        ("dayClassic", BuiltinThemes.dayClassic),
        ("night", BuiltinThemes.night),
        ("nightTinted", BuiltinThemes.nightTinted),
    ]

    // MARK: - ensureContrast primitive

    func testPassingColorIsReturnedByteIdentical() {
        // Blue on white already clears 4.5 — the guard must not touch it.
        XCTAssertEqual(RGBMath.ensureContrast(0x2563EB, on: 0xFFFFFF, floor: 4.5), 0x2563EB)
    }

    func testFailingColorReachesTheFloor() {
        let adjusted = RGBMath.ensureContrast(0x000000, on: 0x000000, floor: 3.0)
        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(adjusted, 0x000000), 3.0)
        XCTAssertNotEqual(adjusted, 0x000000)
    }

    func testAdjustmentIsMinimalNotMaximal() {
        // A near-miss color must shift slightly, not jump to pure white/black.
        let adjusted = RGBMath.ensureContrast(0x4C8DFF, on: 0x2C2C2E, floor: 4.5)
        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(adjusted, 0x2C2C2E), 4.5)
        XCTAssertNotEqual(adjusted, 0xFFFFFF, "minimal blend, never a hard swap to white")
    }

    // MARK: - Matrix: 7 presets × 4 builtin themes

    func testEveryPresetClearsFillFloorOnEveryTheme() {
        for (name, base) in themes {
            for preset in AccentPreset.allCases {
                let theme = base.recolored(accent: preset.rgb(isDark: base.isDark))
                XCTAssertGreaterThanOrEqual(
                    RGBMath.contrastRatio(theme.accent, theme.groupedBackground), 3.0,
                    "\(name)/\(preset) fill vs grouped")
                XCTAssertGreaterThanOrEqual(
                    RGBMath.contrastRatio(theme.accent, theme.elevatedBackground), 3.0,
                    "\(name)/\(preset) fill vs elevated")
            }
        }
    }

    func testEveryPresetClearsTextFloorOnTintedSurfaces() {
        for (name, base) in themes {
            for preset in AccentPreset.allCases {
                let theme = base.recolored(accent: preset.rgb(isDark: base.isDark))
                // Both constraints must hold on the FINAL value — the second
                // guard pass must not undo the first.
                XCTAssertGreaterThanOrEqual(
                    RGBMath.contrastRatio(theme.accentText, theme.controlBackground), 3.0,
                    "\(name)/\(preset) accentText vs controlBackground")
                XCTAssertGreaterThanOrEqual(
                    RGBMath.contrastRatio(theme.accentText, theme.accentSoft), 3.0,
                    "\(name)/\(preset) accentText vs accentSoft")
            }
        }
    }

    func testOnAccentClearsLargeTextFloor() {
        for (name, base) in themes {
            for preset in AccentPreset.allCases {
                let theme = base.recolored(accent: preset.rgb(isDark: base.isDark))
                // Measured against the FILL a button paints, not the raw
                // brand hue: a hue just under the floor is darkened minimally
                // so its label can be white.
                XCTAssertGreaterThanOrEqual(
                    RGBMath.contrastRatio(theme.accentForeground, theme.accentFill), 3.0,
                    "\(name)/\(preset) onAccent")
            }
        }
    }

    /// Non-destructive contract (Rule 1): every curated preset already passes
    /// the fill floor, so the guard must keep its exact brand hue.
    func testCuratedPresetsPassFillGuardByteIdentical() {
        for (name, base) in themes {
            for preset in AccentPreset.allCases {
                let raw = preset.rgb(isDark: base.isDark)
                let adjusted = base.recolored(accent: raw).accent
                if preset == .blue && !base.isDark {
                    // Deliberate exception: the brand blue (#009DFF) sits just
                    // under the 3:1 fill floor on light canvases, so the guard
                    // pulls it minimally to the floor — the disclosed behavior
                    // ("Loox may adjust the selected color slightly…").
                    XCTAssertGreaterThanOrEqual(
                        RGBMath.contrastRatio(adjusted, base.groupedBackground), 3.0,
                        "\(name)/blue guarded fill must clear the floor")
                } else {
                    XCTAssertEqual(adjusted, raw, "\(name)/\(preset) must not be re-tinted")
                }
            }
        }
    }

    /// The ON track must always separate from its white knob — the native iOS
    /// green holds ~2.05:1 against the knob, so 2.0 is the stock-feel floor.
    /// (Regression for the mono-on-dark case: white accent = white track = lost knob.)
    func testSwitchTrackSeparatesFromWhiteKnob() {
        for (name, base) in themes {
            for preset in AccentPreset.allCases {
                let theme = base.recolored(accent: preset.rgb(isDark: base.isDark))
                XCTAssertGreaterThanOrEqual(
                    RGBMath.contrastRatio(theme.switchOn, 0xFFFFFF), 2.0,
                    "\(name)/\(preset) switch track vs knob")
            }
        }
        let mono = BuiltinThemes.night.recolored(accent: 0xFFFFFF)
        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(mono.switchOn, 0xFFFFFF), 2.0)
        XCTAssertNotEqual(mono.switchOn, 0xFFFFFF, "white accent must not stay a white track")
    }

    // MARK: - Extreme inputs (future custom theme / import path)

    func testBlackAccentOnNightStaysVisible() {
        let theme = BuiltinThemes.night.recolored(accent: 0x000000)
        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(theme.accent, theme.groupedBackground), 3.0)
        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(theme.accent, theme.elevatedBackground), 3.0)
        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(theme.accentText, theme.controlBackground), 3.0)
        // The on-accent label stays legible on the adjusted fill too.
        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(theme.accentForeground, theme.accent), 3.0)
    }

    func testWhiteAccentOnDayStaysVisible() {
        let theme = BuiltinThemes.day.recolored(accent: 0xFFFFFF)
        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(theme.accent, theme.groupedBackground), 3.0)
        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(theme.accentText, theme.accentSoft), 3.0)
    }
}
