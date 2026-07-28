import SnapshotTesting
import SwiftUI
import XCTest
@testable import Vaultify

/// The tooltip card's layout. The primary button is the reason this exists: the
/// prominent style ends in `.frame(maxWidth: .infinity)`, which let the pill and
/// the row's Spacer split the free space evenly and parked the button in the
/// middle of the card instead of against its trailing edge.
@MainActor
final class TutorialTooltipSnapshotTests: XCTestCase {
    private func overlay(spotlight: CGRect?, shape: TutorialSpotlightShape,
                         skip: String?) throws -> some View {
        let configuration = try UITestConfiguration.parse(arguments: [
            "Vaultify",
            UITestConfiguration.launchFlag,
            UITestConfiguration.fixtureArgument,
            UITestConfiguration.Fixture.vaultEditSaveRelock.rawValue,
        ])
        let environment = AppEnvironment(uiTestConfiguration: configuration)
        return TutorialSpotlightOverlay(
            spotlight: spotlight,
            shape: shape,
            tooltip: TutorialTooltipContent(
                stepLabel: "Step 1 of 2",
                title: "Your vault health score",
                message: "One number out of 1000, from password strength, reuse, known leaks, and how much two-factor protection you have.",
                primaryTitle: "Next",
                skipTitle: skip),
            allowsInteractionInSpotlight: false,
            onNext: {}, onSkip: {})
            .frame(width: 390, height: 700)
            .background(Color(rgb: environment.theme.active.background))
            .modifier(VaultRootEnvironment(env: environment))
    }

    /// Circular spotlight over a control that is far from square — the vault
    /// health ring's proportions.
    func testSpotlightOverTheHealthRing() throws {
        assertSnapshot(of: try overlay(spotlight: CGRect(x: 65, y: 90, width: 260, height: 218),
                                       shape: .circle, skip: "Skip"),
                       as: .image(layout: .fixed(width: 390, height: 700)),
                       named: "circle-ring")
    }

    /// Closing step: no Skip, so the primary button is alone on its row and any
    /// stray centring is unmissable.
    func testClosingStepCardWithoutSkip() throws {
        assertSnapshot(of: try overlay(spotlight: nil, shape: .rounded, skip: nil),
                       as: .image(layout: .fixed(width: 390, height: 700)),
                       named: "centered-no-skip")
    }
}
