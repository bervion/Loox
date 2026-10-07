import XCTest
@testable import Vaultify

@MainActor final class DestinationVerificationCoordinatorTests: XCTestCase {
    private func state(_ status: String = "pending", id: String = "destination-1") -> RelayAPIClient.DestinationState {
        .init(destinationId: id, status: status, maskedEmail: nil, resendAfterSeconds: nil)
    }
    private func pending() -> ForwardingInbox {
        .init(email: "fixture@example.test", relayDestinationID: "destination-1", verificationStatus: .pending)
    }
    private func repo() -> VaultRepository {
        let session = VaultSession(settings: SettingsStore(), persistentKeyMaterialEnabled: false)
        session.adoptUnlocked(key: [UInt8](repeating: 0x31, count: 32))
        let repository = VaultRepository(store: VaultStore(inMemory: true), session: session, externalSideEffectsEnabled: false)
        repository.reload()
        TestLifetimeRetainer.retain(repository)
        return repository
    }

    func testPersistenceRejectsEmailABAAndDeletedInbox() throws {
        let repository = repo()
        let id = try repository.addManualInbox(email: "a@example.test")
        let original = try XCTUnwrap(repository.inbox(id: id))
        var changed = original; changed.email = "b@example.test"
        try repository.updateInbox(changed)
        changed = try XCTUnwrap(repository.inbox(id: id)); changed.email = "a@example.test"
        try repository.updateInbox(changed)
        XCTAssertFalse(try repository.applyDestinationState(state("verified"), snapshot: original, allowDestinationChange: true))
        XCTAssertEqual(repository.inbox(id: id)?.verificationStatus, .unverified)
        let live = try XCTUnwrap(repository.inbox(id: id))
        try repository.deleteInbox(live)
        XCTAssertFalse(try repository.applyDestinationState(state("verified"), snapshot: live, allowDestinationChange: true))
    }

    func testDelayedBeginCannotDowngradeVerifiedAndUnchangedIsNoOp() throws {
        let repository = repo()
        let id = try repository.addManualInbox(email: "fixture@example.test")
        let first = try XCTUnwrap(repository.inbox(id: id))
        XCTAssertTrue(try repository.applyDestinationState(state(), snapshot: first, allowDestinationChange: true))
        let pending = try XCTUnwrap(repository.inbox(id: id))
        XCTAssertTrue(try repository.applyDestinationState(state("verified"), snapshot: pending, allowDestinationChange: false))
        let record = try XCTUnwrap(repository.store.inboxRecord(id: id))
        let sealed = record.sealed; let updatedAt = record.updatedAt
        XCTAssertFalse(try repository.applyDestinationState(state(), snapshot: pending, allowDestinationChange: true))
        let verified = try XCTUnwrap(repository.inbox(id: id))
        XCTAssertFalse(try repository.applyDestinationState(state("verified"), snapshot: verified, allowDestinationChange: false))
        XCTAssertEqual(record.sealed, sealed)
        XCTAssertEqual(record.updatedAt, updatedAt)
        XCTAssertEqual(repository.inbox(id: id)?.verificationStatus, .verified)
    }

    func testRefreshCannotAssignDifferentDestinationAndMalformedNeverVerifies() throws {
        let repository = repo()
        let id = try repository.addManualInbox(email: "fixture@example.test")
        let first = try XCTUnwrap(repository.inbox(id: id))
        _ = try repository.applyDestinationState(state(), snapshot: first, allowDestinationChange: true)
        let pending = try XCTUnwrap(repository.inbox(id: id))
        XCTAssertThrowsError(try repository.applyDestinationState(state("verified", id: "other"), snapshot: pending, allowDestinationChange: false))
        XCTAssertThrowsError(try repository.applyDestinationState(state("garbled"), snapshot: pending, allowDestinationChange: false))
        XCTAssertEqual(repository.inbox(id: id)?.verificationStatus, .pending)
    }

    func testDestinationIDABACannotAcceptOlderResponse() throws {
        let repository = repo()
        let id = try repository.addManualInbox(email: "fixture@example.test")
        _ = try repository.applyDestinationState(state(), snapshot: try XCTUnwrap(repository.inbox(id: id)), allowDestinationChange: true)
        let original = try XCTUnwrap(repository.inbox(id: id))
        _ = try repository.applyDestinationState(state(id: "destination-2"), snapshot: original, allowDestinationChange: true)
        let changed = try XCTUnwrap(repository.inbox(id: id))
        _ = try repository.applyDestinationState(state(), snapshot: changed, allowDestinationChange: true)
        XCTAssertFalse(try repository.applyDestinationState(state("verified"), snapshot: original, allowDestinationChange: false))
        XCTAssertEqual(repository.inbox(id: id)?.verificationStatus, .pending)
    }

    func testRetryAfterAcceptsSecondsAndHTTPDate() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let url = try XCTUnwrap(URL(string: "https://example.test"))
        let seconds = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "120"]))
        XCTAssertEqual(RelayAPIClient.retryAfter(from: seconds, now: now), 120)
        let date = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "Thu, 01 Jan 1970 00:18:40 GMT"]))
        XCTAssertEqual(RelayAPIClient.retryAfter(from: date, now: now), 120)
    }

    func testSimultaneousChecksJoinOneRequest() async throws {
        let inbox = pending()
        var requests = 0
        var release: CheckedContinuation<Void, Never>?
        let expected = state()
        let coordinator = DestinationVerificationCoordinator(inboxes: { [inbox] }, policy: { true }, begin: { _ in expected }, refresh: { _ in
            requests += 1
            await withCheckedContinuation { release = $0 }
            return expected
        })
        coordinator.setLifecycle(active: true, unlocked: true)
        let first = Task { try await coordinator.refreshNow(inbox) }
        for _ in 0..<100 where release == nil { await Task.yield() }
        let second = Task { try await coordinator.refreshNow(inbox) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(requests, 1)
        try XCTUnwrap(release).resume()
        _ = try await first.value; _ = try await second.value
        XCTAssertTrue(coordinator.checkingInboxIDs.isEmpty)
    }

    func testNewPendingStateWakesVisibleScopeAndVerifiedStopsIt() async throws {
        var current = ForwardingInbox(email: "fixture@example.test")
        var requests = 0
        let expected = state("verified")
        let coordinator = DestinationVerificationCoordinator(inboxes: { [current] }, policy: { true }, begin: { _ in expected }, refresh: { _ in
            requests += 1
            current.verificationStatus = .verified
            return expected
        })
        coordinator.setLifecycle(active: true, unlocked: true)
        let scope = coordinator.register([current.id])
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(requests, 0)
        current.relayDestinationID = "destination-1"
        current.verificationStatus = .pending
        coordinator.stateChanged()
        for _ in 0..<100 where requests == 0 { await Task.yield() }
        XCTAssertEqual(requests, 1)
        coordinator.stateChanged()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(requests, 1)
        coordinator.unregister(scope)
        coordinator.setLifecycle(active: false, unlocked: false)
    }

    func testBeginWaitsForInFlightStatusOperation() async throws {
        let inbox = pending()
        let expected = state()
        var refreshStarted = false
        var begins = 0
        var release: CheckedContinuation<Void, Never>?
        let coordinator = DestinationVerificationCoordinator(inboxes: { [inbox] }, policy: { true }, begin: { _ in
            begins += 1; return expected
        }, refresh: { _ in
            refreshStarted = true
            await withCheckedContinuation { release = $0 }
            return expected
        })
        coordinator.setLifecycle(active: true, unlocked: true)
        let check = Task { try await coordinator.refreshNow(inbox) }
        for _ in 0..<100 where !refreshStarted { await Task.yield() }
        let send = Task { try await coordinator.begin(inbox) }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(begins, 0)
        try XCTUnwrap(release).resume()
        _ = try await check.value; _ = try await send.value
        XCTAssertEqual(begins, 1)
    }

    func testRollingBudgetAppliesToManualChecksAndRecovers() async throws {
        let inbox = pending()
        var instant = Date(timeIntervalSince1970: 1_000)
        var requests = 0
        let expected = state()
        let coordinator = DestinationVerificationCoordinator(inboxes: { [inbox] }, policy: { true }, begin: { _ in expected }, refresh: { _ in
            requests += 1; return expected
        }, now: { instant })
        coordinator.setLifecycle(active: true, unlocked: true)
        for _ in 0..<30 { _ = try await coordinator.refreshNow(inbox) }
        do { _ = try await coordinator.refreshNow(inbox); XCTFail("exceeded rolling budget") }
        catch DestinationVerificationCoordinator.Failure.throttled { }
        XCTAssertEqual(requests, 30)
        instant = instant.addingTimeInterval(61)
        _ = try await coordinator.refreshNow(inbox)
        XCTAssertEqual(requests, 31)
    }

    func testRetryAfterIsAuthoritativeAcrossForeground() async throws {
        let inbox = pending()
        var instant = Date(timeIntervalSince1970: 1_000)
        var requests = 0
        let expected = state()
        let coordinator = DestinationVerificationCoordinator(inboxes: { [inbox] }, policy: { true }, begin: { _ in expected }, refresh: { _ in
            requests += 1
            if requests == 1 { throw RelayAPIClient.DestinationStatusFailure.throttled(retryAfter: 120) }
            return expected
        }, now: { instant }, jitter: { 0 })
        coordinator.setLifecycle(active: true, unlocked: true)
        do { _ = try await coordinator.refreshNow(inbox); XCTFail("expected 429") } catch { }
        coordinator.setLifecycle(active: false, unlocked: true)
        coordinator.setLifecycle(active: true, unlocked: true)
        instant = instant.addingTimeInterval(119)
        do { _ = try await coordinator.refreshNow(inbox); XCTFail("Retry-After ignored") } catch { }
        XCTAssertEqual(requests, 1)
        instant = instant.addingTimeInterval(2)
        _ = try await coordinator.refreshNow(inbox)
        XCTAssertEqual(requests, 2)
    }

    func testLockCancelsFlightAndRejectsNewRequests() async throws {
        let inbox = pending(); let expected = state()
        var entered = false
        let coordinator = DestinationVerificationCoordinator(inboxes: { [inbox] }, policy: { true }, begin: { _ in expected }, refresh: { _ in
            entered = true
            try await Task.sleep(for: .seconds(60))
            return expected
        })
        coordinator.setLifecycle(active: true, unlocked: true)
        let flight = Task { try await coordinator.refreshNow(inbox) }
        for _ in 0..<100 where !entered { await Task.yield() }
        coordinator.setLifecycle(active: true, unlocked: false)
        do { _ = try await flight.value; XCTFail("locked flight accepted") } catch { }
        do { _ = try await coordinator.refreshNow(inbox); XCTFail("locked request admitted") } catch { }
        XCTAssertTrue(coordinator.errors.isEmpty)
        XCTAssertTrue(coordinator.checkingInboxIDs.isEmpty)
    }

    func testRemoteStatusKeepsOperatorModeAndCancelledProbeReleasesExactlyOnce() throws {
        let suite = "destination-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let capabilities = CapabilityStore(reachability: NetworkReachabilityMonitor(monitoringEnabled: false, initialSatisfied: true), defaults: defaults)
        for mode in [CapabilityServiceMode.active, .degraded, .maintenance, .disabled] {
            capabilities.applyOperatorPolicy(.privateEmail, .init(mode: mode, retryAfter: nil))
            XCTAssertTrue(capabilities.canRefreshDestinationStatus)
            let token = try XCTUnwrap(capabilities.admitDestinationStatus())
            capabilities.finishDestinationStatus(token, outcome: .responded)
            XCTAssertEqual(capabilities.modes[.privateEmail], mode)
            XCTAssertEqual(capabilities.health[.privateEmail], .healthy)
        }
        let instant = Date(timeIntervalSince1970: 1_000)
        for _ in 0..<3 { capabilities.noteInfrastructureFailure(.privateEmail, now: instant) }
        let probe = try XCTUnwrap(capabilities.admitDestinationStatus(now: instant.addingTimeInterval(31)))
        XCTAssertNil(capabilities.admitDestinationStatus(now: instant.addingTimeInterval(31)))
        capabilities.finishDestinationStatus(probe, outcome: .cancelled, now: instant.addingTimeInterval(31))
        capabilities.finishDestinationStatus(probe, outcome: .infrastructureFailure, now: instant.addingTimeInterval(31))
        XCTAssertNotNil(capabilities.admitDestinationStatus(now: instant.addingTimeInterval(31)))
        XCTAssertEqual(capabilities.modes[.privateEmail], .disabled)
        capabilities.applyOperatorPolicy(.privateEmail, .init(mode: .active, retryAfter: nil), disabledOps: [.read])
        XCTAssertFalse(capabilities.canRefreshDestinationStatus)
        XCTAssertEqual(capabilities.availability(.privateEmail, operation: .read), .available)
    }
}
