import SnapshotTesting
import SwiftUI
import XCTest
@testable import Vaultify

@MainActor
final class LockControlSnapshotTests: XCTestCase {
    func testSlideToUnlockLight() throws {
        let configuration = try UITestConfiguration.parse(arguments: [
            "Vaultify",
            UITestConfiguration.launchFlag,
            UITestConfiguration.fixtureArgument,
            UITestConfiguration.Fixture.vaultEditSaveRelock.rawValue,
        ])
        let environment = AppEnvironment(uiTestConfiguration: configuration)
        let subject = SlideToUnlock(onComplete: {})
            .padding(24)
            .frame(width: 390, height: 120)
            .background(Color(rgb: environment.theme.active.background))
            .modifier(VaultRootEnvironment(env: environment))

        assertSnapshot(
            of: subject,
            as: .image(layout: .fixed(width: 390, height: 120)),
            named: "light-en"
        )
    }
}
