import SnapshotTesting
import SwiftUI
import XCTest
@testable import Vaultify

/// `InlineConfirm` replaced five `confirmationDialog`s that could never run
/// their action from inside a sheet. Only the quick-link one can be exercised
/// at runtime here — the four Approval-Mode confirmations need iCloud and a
/// second device to reach — so the component itself is pinned instead, with the
/// exact copy each site passes.
///
/// Vietnamese is the load-bearing case: it is the longest of the three
/// languages, and the hand-over sentence is the longest string in the set. If a
/// confirmation is going to clip or push its buttons off a row, it does it here
/// first.
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

    /// The longest copy in the set, and the one whose button label is a full
    /// sentence — the tightest layout of the five.
    func testHandOverSecret() throws {
        let environment = try makeSnapshotEnvironment()
        assertSnapshot(
            of: subject("They'll be able to use it without asking you, on their own device. Revoking later only stops updates; a secret already handed over can't be pulled back. To truly revoke it, change it at the website.",
                        "Hand over: can't be taken back",
                        environment: environment, height: 260),
            as: .scaledImage(width: 342, height: 260),
            named: "hand-over-secret")
    }

    func testHandOverPasskey() throws {
        let environment = try makeSnapshotEnvironment()
        assertSnapshot(
            of: subject("They'll be able to use it without asking you, on their own device. Revoking later only stops updates; a key already handed over can't be pulled back.",
                        "Hand over: can't be taken back",
                        environment: environment, height: 230),
            as: .scaledImage(width: 342, height: 230),
            named: "hand-over-passkey")
    }
}
