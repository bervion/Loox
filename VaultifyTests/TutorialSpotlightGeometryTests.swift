import CoreGraphics
import XCTest
@testable import Vaultify

/// The spotlight's shape rules. A circular highlight is the only one whose cut
/// cannot be taken from the control's own bounds, and the vault-health ring
/// (260×218) is the case that proved it.
@MainActor
final class TutorialSpotlightGeometryTests: XCTestCase {
    private let ring = CGRect(x: 77, y: 220, width: 260, height: 218)
    private let padding: CGFloat = 8

    func testCircleSpotlightOnAWideControlStaysARealCircle() {
        let hole = TutorialSpotlightGeometry.hole(around: ring, shape: .circle, padding: padding)
        XCTAssertEqual(hole.width, hole.height, accuracy: 0.001,
                       "a circular spotlight must be cut from a square, not stretched into an oval")
        XCTAssertEqual(TutorialSpotlightGeometry.cornerRadius(for: hole, shape: .circle),
                       hole.width / 2, accuracy: 0.001)
    }

    func testCircleSpotlightCoversTheWholeControlAndStaysCentredOnIt() {
        let hole = TutorialSpotlightGeometry.hole(around: ring, shape: .circle, padding: padding)
        XCTAssertEqual(hole.midX, ring.midX, accuracy: 0.001)
        XCTAssertEqual(hole.midY, ring.midY, accuracy: 0.001)
        // Squaring takes the LONGER side, so nothing the control draws is clipped.
        XCTAssertEqual(hole.width, ring.width + 2 * padding, accuracy: 0.001)
        XCTAssertTrue(hole.contains(ring), "the cut must not crop the control it highlights")
    }

    func testCapsuleAndRoundedKeepTheControlsOwnProportions() {
        let capsule = TutorialSpotlightGeometry.hole(around: ring, shape: .capsule, padding: padding)
        XCTAssertEqual(capsule.width, ring.width + 2 * padding, accuracy: 0.001)
        XCTAssertEqual(capsule.height, ring.height + 2 * padding, accuracy: 0.001)
        XCTAssertEqual(TutorialSpotlightGeometry.cornerRadius(for: capsule, shape: .capsule),
                       capsule.height / 2, accuracy: 0.001)

        let rounded = TutorialSpotlightGeometry.hole(around: ring, shape: .rounded, padding: padding)
        XCTAssertEqual(rounded, capsule, "only the radius differs between these two shapes")
        XCTAssertEqual(TutorialSpotlightGeometry.cornerRadius(for: rounded, shape: .rounded), Radius.md)
    }

    /// At a radius of half the side, Apple's continuous curve draws a squircle
    /// with straight runs down its sides, so a "circle" cut that way shows seams.
    func testRoundShapesUseTheCircularArcAndCardsKeepTheContinuousCurve() {
        XCTAssertEqual(TutorialSpotlightGeometry.cornerStyle(for: .circle), .circular)
        XCTAssertEqual(TutorialSpotlightGeometry.cornerStyle(for: .capsule), .circular)
        XCTAssertEqual(TutorialSpotlightGeometry.cornerStyle(for: .rounded), .continuous)
    }

    func testAlreadySquareControlIsUntouchedByTheSquaringStep() {
        let square = CGRect(x: 40, y: 40, width: 120, height: 120)
        XCTAssertEqual(TutorialSpotlightGeometry.hole(around: square, shape: .circle, padding: padding),
                       square.insetBy(dx: -padding, dy: -padding))
    }

    func testEntranceStartsWiderThanTheSettledHoleAndSharesItsCentre() {
        let settled = TutorialSpotlightGeometry.hole(around: ring, shape: .rounded, padding: padding)
        let entering = TutorialSpotlightGeometry.hole(around: ring, shape: .rounded,
                                                      padding: padding, expansion: 26)
        XCTAssertGreaterThan(entering.width, settled.width)
        XCTAssertGreaterThan(entering.height, settled.height)
        XCTAssertEqual(entering.midX, settled.midX, accuracy: 0.001)
        XCTAssertEqual(entering.midY, settled.midY, accuracy: 0.001)
    }
}
