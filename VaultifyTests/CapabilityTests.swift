import XCTest
@testable import Vaultify

/// Optional-capability layer: pure resolver (BE-parity operation gate,
/// distinct states — INV-CAP-04), per-service circuit breaker, structured
/// problem+json parsing (INV-CAP-07), and CapabilityStore state movement
/// (operator persistence, preference independence — INV-CAP-09).
@MainActor
final class CapabilityTests: XCTestCase {

    // MARK: Resolver

    func testReadIsNeverGated() {
        // INV-CAP-05/10: local records stay visible in EVERY state.
        for mode in [CapabilityServiceMode.active, .degraded, .maintenance, .disabled, .retired] {
            let availability = CapabilityResolver.availability(
                userPreference: false, mode: mode, health: .outage,
                connectivity: .offline, breakerOpen: true, operation: .read)
            XCTAssertEqual(availability, .available, "read gated under \(mode)")
        }
    }

    func testOperationGateMirrorsBackendTable() {
        // Parity with loox-relay/loox-link capability.ts: growth stops first,
        // delete/revoke survive maintenance/disabled, retired stops everything.
        XCTAssertTrue(CapabilityResolver.operationEnabled(mode: .active, operation: .create))
        XCTAssertFalse(CapabilityResolver.operationEnabled(mode: .degraded, operation: .create))
        XCTAssertTrue(CapabilityResolver.operationEnabled(mode: .degraded, operation: .mutate))
        for mode in [CapabilityServiceMode.maintenance, .disabled] {
            XCTAssertFalse(CapabilityResolver.operationEnabled(mode: mode, operation: .create))
            XCTAssertFalse(CapabilityResolver.operationEnabled(mode: mode, operation: .mutate))
            XCTAssertTrue(CapabilityResolver.operationEnabled(mode: mode, operation: .delete))
            XCTAssertTrue(CapabilityResolver.operationEnabled(mode: mode, operation: .revoke))
        }
        XCTAssertFalse(CapabilityResolver.operationEnabled(mode: .retired, operation: .revoke))
    }

    func testDistinctStatesNeverCollapse() {
        // INV-CAP-04: offline ≠ outage ≠ maintenance ≠ disabled ≠ retired.
        func resolve(mode: CapabilityServiceMode = .active, health: CapabilityHealth = .healthy,
                     connectivity: ConnectivityState = .online, breaker: Bool = false,
                     pref: Bool = true) -> CapabilityAvailability {
            CapabilityResolver.availability(userPreference: pref, mode: mode, health: health,
                                            connectivity: connectivity, breakerOpen: breaker,
                                            retryAfter: 900, operation: .create)
        }
        XCTAssertEqual(resolve(), .available)
        XCTAssertEqual(resolve(connectivity: .offline), .offline)
        XCTAssertEqual(resolve(health: .outage), .temporarilyUnavailable)
        XCTAssertEqual(resolve(breaker: true), .temporarilyUnavailable)
        XCTAssertEqual(resolve(mode: .maintenance), .maintenance(retryAfter: 900))
        XCTAssertEqual(resolve(mode: .disabled), .disabledByOperator)
        XCTAssertEqual(resolve(mode: .retired), .retired)
        XCTAssertEqual(resolve(pref: false), .disabledByUser)
        // Operator state outranks connectivity: maintenance while offline is
        // still maintenance (the user should see the verified state).
        XCTAssertEqual(resolve(mode: .maintenance, connectivity: .offline),
                       .maintenance(retryAfter: 900))
    }

    // MARK: Circuit breaker

    func testBreakerOpensOnThreeConsecutiveFailuresAndEscalates() {
        var breaker = CapabilityCircuitBreaker()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(breaker.allowRequest(now: t0))
        breaker.recordInfrastructureFailure(now: t0)
        breaker.recordInfrastructureFailure(now: t0)
        XCTAssertFalse(breaker.isOpen)
        breaker.recordInfrastructureFailure(now: t0)          // 3rd consecutive → open 30s
        XCTAssertTrue(breaker.isOpen)
        XCTAssertFalse(breaker.allowRequest(now: t0.addingTimeInterval(10)))
        // Expiry → half-open admits exactly ONE probe.
        XCTAssertTrue(breaker.allowRequest(now: t0.addingTimeInterval(31)))
        XCTAssertFalse(breaker.allowRequest(now: t0.addingTimeInterval(31)))
        // Probe fails → reopen with escalation (60s).
        breaker.recordInfrastructureFailure(now: t0.addingTimeInterval(31))
        XCTAssertFalse(breaker.allowRequest(now: t0.addingTimeInterval(31 + 45)))
        XCTAssertTrue(breaker.allowRequest(now: t0.addingTimeInterval(31 + 61)))
        // Probe succeeds → closed, escalation reset.
        breaker.recordSuccess()
        XCTAssertFalse(breaker.isOpen)
        XCTAssertTrue(breaker.allowRequest(now: t0.addingTimeInterval(200)))
    }

    func testBreakerOpensOnSixtyPercentWindowRate() {
        var breaker = CapabilityCircuitBreaker()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        // f s f s f — never 3 consecutive, but 3/5 = 60% once the window fills.
        breaker.recordInfrastructureFailure(now: t0)
        breaker.recordSuccess()
        breaker.recordInfrastructureFailure(now: t0)
        breaker.recordSuccess()
        breaker.recordInfrastructureFailure(now: t0)
        XCTAssertTrue(breaker.isOpen)
    }

    // MARK: Structured signal parsing (INV-CAP-07)

    private func response(_ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api-relay.looxpassword.com/v1/relay/aliases")!,
                        statusCode: status, httpVersion: nil, headerFields: headers)!
    }

    func testCapabilitySignalParsesHeaderAndBody() throws {
        let body = Data(#"{"code":"capability_maintenance","retry_after_seconds":900}"#.utf8)
        let failure = RelayAPIClient.capabilitySignal(
            from: response(503, headers: ["X-Loox-Service-State": "maintenance"]), data: body)
        XCTAssertEqual(failure, .capability(.maintenance, retryAfter: 900))
        // Body-only (no header) still resolves via the code.
        let retired = RelayAPIClient.capabilitySignal(
            from: response(410), data: Data(#"{"code":"capability_retired"}"#.utf8))
        XCTAssertEqual(retired, .capability(.retired, retryAfter: nil))
    }

    func testPlainInfrastructure503IsNeverAnOperatorSignal() {
        // A Cloudflare 503 with no capability contract must NOT read as
        // maintenance/disabled/retired (INV-CAP-07).
        XCTAssertNil(RelayAPIClient.capabilitySignal(from: response(503), data: Data()))
        XCTAssertNil(RelayAPIClient.capabilitySignal(
            from: response(503), data: Data(#"{"error":"upstream"}"#.utf8)))
    }

    // MARK: Health-probe parsing + App Group snapshot

    func testReadyReportStateParses() {
        XCTAssertEqual(CapabilityHealthProbe.parseState(
            Data(#"{"ready":true,"state":"maintenance","checks":{}}"#.utf8)), .maintenance)
        XCTAssertNil(CapabilityHealthProbe.parseState(Data(#"{"ok":true}"#.utf8)))
        XCTAssertNil(CapabilityHealthProbe.parseState(Data()))
    }

    func testSnapshotRoundTripAndCorruptFallback() {
        let suite = "capability-snapshot-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        // Missing snapshot → nil ("unknown"), never a gate on local behavior.
        XCTAssertNil(CapabilitySnapshot.read(defaults: defaults))
        CapabilitySnapshot.write(modes: [.privateEmail: .maintenance, .shareLink: .active],
                                 defaults: defaults)
        let snapshot = CapabilitySnapshot.read(defaults: defaults)
        XCTAssertEqual(snapshot?.mode(for: .privateEmail), .maintenance)
        XCTAssertEqual(snapshot?.mode(for: .shareLink), .active)
        // Corrupt data → nil, not a crash and not a false state.
        defaults.set(Data([0xFF, 0x00]), forKey: "capability_snapshot_v1")
        XCTAssertNil(CapabilitySnapshot.read(defaults: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: Store

    private func makeStore(_ suite: String) -> (CapabilityStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = CapabilityStore(reachability: NetworkReachabilityMonitor(), defaults: defaults)
        return (store, defaults)
    }

    func testOperatorSignalPersistsButInfraFailureNeverChangesMode() {
        let suite = "capability-tests-\(UUID().uuidString)"
        let (store, defaults) = makeStore(suite)
        store.noteOperatorSignal(.privateEmail, .init(mode: .maintenance, retryAfter: 900))
        XCTAssertEqual(store.modes[.privateEmail], .maintenance)
        // Infra failure: health/breaker only — verified mode untouched.
        store.noteInfrastructureFailure(.privateEmail)
        XCTAssertEqual(store.modes[.privateEmail], .maintenance)
        XCTAssertEqual(store.health[.privateEmail], .outage)
        // …and it survives a relaunch (new store on the same defaults).
        let store2 = CapabilityStore(reachability: NetworkReachabilityMonitor(), defaults: defaults)
        XCTAssertEqual(store2.modes[.privateEmail], .maintenance)
        defaults.removePersistentDomain(forName: suite)
    }

    func testCapabilitiesFailIndependentlyAndPreferenceIsUntouched() {
        let suite = "capability-tests-\(UUID().uuidString)"
        let (store, defaults) = makeStore(suite)
        store.setUserPreference(.privateEmail, enabled: true)
        // Relay melts down: 3 infra failures open ITS breaker only (INV-CAP-03).
        // (Asserted via allowRequest — availability() also folds in live device
        // connectivity, which is .offline in the test sandbox.)
        for _ in 0..<3 { store.noteInfrastructureFailure(.privateEmail) }
        XCTAssertFalse(store.allowRequest(.privateEmail))
        XCTAssertTrue(store.allowRequest(.shareLink))        // independent breaker
        XCTAssertEqual(store.health[.privateEmail], .outage)
        XCTAssertEqual(store.health[.shareLink], .unknown)   // untouched
        // Outage never flips the user's preference (INV-CAP-09).
        XCTAssertTrue(store.userPreference(.privateEmail))
        defaults.removePersistentDomain(forName: suite)
    }
}
