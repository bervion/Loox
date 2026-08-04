import SnapshotTesting
import SwiftUI
import XCTest
@testable import Vaultify

@MainActor
final class LockControlSnapshotTests: XCTestCase {
    func testSlideToUnlockLight() throws {
        let environment = try makeSnapshotEnvironment()
        let subject = SlideToUnlock(onComplete: {})
            .padding(24)
            .frame(width: 390, height: 120)
            .background(Color(rgb: environment.theme.active.background))
            .modifier(VaultRootEnvironment(env: environment))

        assertSnapshot(
            of: subject,
            as: .scaledImage(width: 390, height: 120),
            named: "light-en"
        )
    }
}
