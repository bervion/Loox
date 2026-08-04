import Foundation
@testable import Vaultify

/// Builds `AppEnvironment` instances for tests and keeps them alive for the
/// life of the test host.
///
/// Why retain them:
///
/// `AppEnvironment.init` installs closures onto the process-wide
/// `LooxEntitlementClientHooks` statics, so constructing a second environment
/// drops the previous one's `LooxEntitlementCoordinator`. That is a
/// `@MainActor @Observable final class`, which means the compiler synthesises an
/// *isolated* deallocating deinit for it, and the iOS 17.3 deployment floor
/// routes that through the `swift_task_deinitOnExecutorMainActorBackDeploy`
/// shim. On Xcode 27.0 / iOS 26.3 the shim aborts inside libmalloc
/// ("pointer being freed was not allocated") and takes the whole test host down
/// mid-suite — which then marks every test that was in flight as failed, with
/// no assertion failure to point at.
///
/// Retaining is not a workaround for a product defect. The shipping app builds
/// exactly one environment at launch and never deallocates it, so a test that
/// holds on to what it built is modelling the app; a test that churns
/// environments is not. The same reasoning produced `SnapshotAppEnvironment` in
/// the snapshot target.
///
/// If the deployment floor ever rises above iOS 18, the shim disappears and this
/// can go back to plain `AppEnvironment(...)`.
@MainActor
enum TestAppEnvironment {
    private static var retained: [AppEnvironment] = []

    /// A fresh, fully isolated environment that will not be deallocated.
    static func make(uiTestConfiguration: UITestConfiguration = .disabled) -> AppEnvironment {
        let environment = AppEnvironment(uiTestConfiguration: uiTestConfiguration)
        retained.append(environment)
        return environment
    }
}
