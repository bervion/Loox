import Foundation
import Network

/// Layer A of the shared-vault access gate: a live `NWPathMonitor` wrapper.
///
/// A satisfied network path is a PRECONDITION, never an authorization
/// (INV-02) — Layer B (authoritative grant verification) decides actual
/// access. Deliberately named `hasSatisfiedNetworkPath`, not "isOnline":
/// a satisfied path says nothing about CloudKit being reachable or the
/// account being usable.
///
/// Starts pessimistic (`false`) so consumers fail closed until the first
/// path update arrives (INV-03). Lives in VaultifyCore so the AutoFill
/// extension applies the same gate.
@MainActor @Observable final class NetworkReachabilityMonitor {
    private(set) var hasSatisfiedNetworkPath = false

    @ObservationIgnored private let monitor: NWPathMonitor?

    init(monitoringEnabled: Bool = true, initialSatisfied: Bool = false) {
        hasSatisfiedNetworkPath = initialSatisfied
        guard monitoringEnabled else {
            monitor = nil
            return
        }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.hasSatisfiedNetworkPath = satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.bervion.vaultify.reachability"))
    }

    // `nonisolated` on purpose. This class is `@MainActor`, and under the Swift
    // 6.2 runtime a main-actor class gets an ISOLATED deinit: releasing it off
    // the main actor makes the runtime hop to run the deinit, which aborts in
    // the test host. `NWPathMonitor.cancel()` is thread-safe, so there is no
    // reason for this teardown to be isolated at all.
    nonisolated deinit { monitor?.cancel() }
}
