import XCTest
import SwiftUI
@testable import Vaultify

/// The detail row's strength read-out is a label plus a ring, and the two must always agree:
/// the ring's fill says "how full" and its colour says "is this a problem". A grade that filled
/// the ring further while turning it redder would be actively misleading, so the ordering and
/// the colour banding are pinned here rather than left to the view.
final class PasswordStrengthRingTests: XCTestCase {

    func testFillRisesWithTheGrade() {
        let fractions = PasswordGrade.allCases.map(\.fraction)
        XCTAssertEqual(fractions, fractions.sorted(), "a better grade must never fill the ring less")
        XCTAssertEqual(PasswordGrade.veryWeak.fraction, 0.2, accuracy: 0.001)
        XCTAssertEqual(PasswordGrade.excellent.fraction, 1.0, accuracy: 0.001,
                       "the top grade must close the ring, or the gauge has no visible maximum")
    }

    func testColourBandsMatchTheThreeStrengthColours() {
        XCTAssertEqual(VaultColors.strength(grade: .veryWeak), VaultColors.strengthWeak)
        XCTAssertEqual(VaultColors.strength(grade: .weak), VaultColors.strengthWeak)
        XCTAssertEqual(VaultColors.strength(grade: .fair), VaultColors.strengthMedium)
        XCTAssertEqual(VaultColors.strength(grade: .strong), VaultColors.strengthStrong)
        XCTAssertEqual(VaultColors.strength(grade: .excellent), VaultColors.strengthStrong)
    }

    func testEveryGradeIsLabelled() {
        // The ring is the glanceable half; the label is the precise one. A blank label would
        // leave the ring saying "some amount of good" with nothing to anchor it.
        for grade in PasswordGrade.allCases {
            XCTAssertFalse(String(localized: grade.title).isEmpty, "\(grade) has no title")
        }
    }

    func testWeakAndStrongPasswordsLandInDifferentBands() {
        // Guards the wiring end to end: the row evaluates the real password text, so a change
        // that made every value grade the same would show one colour for everything.
        let weak = PasswordStrengthEngine.evaluate("password").grade
        let strong = PasswordStrengthEngine.evaluate("7Kq!vZ2m@Rt9#Lw4$Xb8").grade
        XCTAssertLessThan(weak, strong)
        XCTAssertEqual(VaultColors.strength(grade: weak), VaultColors.strengthWeak)
        XCTAssertEqual(VaultColors.strength(grade: strong), VaultColors.strengthStrong)
    }
}
