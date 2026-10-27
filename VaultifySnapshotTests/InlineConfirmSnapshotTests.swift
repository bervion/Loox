import SnapshotTesting
import SwiftUI
import XCTest
@testable import Vaultify

/// `InlineConfirm` replaced five `confirmationDialog`s that could never run
/// their action from inside a sheet. Only the quick-link one can be exercised
/// at runtime here — the Approval-Mode confirmations need iCloud and a second
/// device to reach — so the component itself is pinned instead, with the exact
/// copy each site passes. The two hand-over confirmations have since moved to
/// their own sheet step (`ShareHandOverConfirmView`, pinned in
/// `ShareDetailsSnapshotTests`).
@MainActor
final class InlineConfirmSnapshotTests: XCTestCase {

    private func subject(_ message: LocalizedStringKey,
                         _ confirmTitle: LocalizedStringKey,
                         environment: AppEnvironment,
                         width: CGFloat = 342,
                         height: CGFloat = 190) -> some View {
        InlineConfirm(message: message, confirmTitle: confirmTitle,
                      onCancel: {}, onConfirm: {})
            .padding(16)
            .frame(width: width, height: height)
            .background(Color(rgb: environment.theme.active.background))
            .modifier(VaultRootEnvironment(env: environment))
    }

    func testRevokeLink() throws {
        let environment = try makeSnapshotEnvironment()
        assertSnapshot(
            of: subject("Anyone who has the link loses access immediately.",
                        "Revoke Link", environment: environment),
            as: .scaledImage(width: 342, height: 190),
            named: "revoke-link")
    }

    func testRevokeAccess() throws {
        let environment = try makeSnapshotEnvironment()
        assertSnapshot(
            of: subject("They can't request codes anymore. Values that were already shared stay on their device.",
                        "Revoke access", environment: environment),
            as: .scaledImage(width: 342, height: 190),
            named: "revoke-access")
    }

    func testStopSharing() throws {
        let environment = try makeSnapshotEnvironment()
        assertSnapshot(
            of: subject("They lose access to this item. Anything else you shared with them stays. Values already handed over stay on their device.",
                        "Stop sharing", environment: environment),
            as: .scaledImage(width: 342, height: 220),
            named: "stop-sharing")
    }
}
