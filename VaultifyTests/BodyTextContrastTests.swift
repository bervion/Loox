import XCTest
@testable import Vaultify

/// Body-sized supporting and status copy must remain readable on the actual
/// content surfaces, including after a live accent/theme switch.
final class BodyTextContrastTests: XCTestCase {
    func testBodyRolesClearFourPointFiveAcrossAllBuiltinThemesAndAccents() {
        let themes = [BuiltinThemes.day, BuiltinThemes.dayClassic, BuiltinThemes.night, BuiltinThemes.nightTinted]
        for base in themes {
            for accent in AccentPreset.allCases {
                let theme = base.recolored(accent: accent.rgb(isDark: base.isDark))
                let roles = [theme.secondaryBodyText, theme.successBodyText, theme.warningBodyText]
                let surfaces = [theme.background, theme.secondaryBackground, theme.groupedBackground,
                                theme.elevatedBackground, theme.controlBackground, theme.surfacePressed]
                for role in roles {
                    for surface in surfaces {
                        XCTAssertGreaterThanOrEqual(RGBMath.contrastRatio(role, surface), 4.5,
                            "Body role on theme \(base.reference), accent \(accent), surface \(surface)")
                    }
                }
            }
        }
    }
}
