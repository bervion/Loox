import Foundation
import XCTest
@testable import Vaultify

@MainActor
final class ForwardingInboxServiceTests: XCTestCase {
    private func fixture() throws -> (VaultRepository, VaultSession, CapabilityStore, ForwardingInbox) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "inbox-service-\(UUID().uuidString)"))
        let session = VaultSession(settings: SettingsStore(defaults: defaults, mirrorToSharedConfig: false),
                                   persistentKeyMaterialEnabled: false)
        session.adoptUnlocked(key: [UInt8](repeating: 0x38, count: 32), publishSharedSession: false)
        let repository = VaultRepository(store: VaultStore(inMemory: true), session: session, externalSideEffectsEnabled: false)
        repository.reload()
        let id = try repository.addManualInbox(email: "fixture@example.test")
        var inbox = try XCTUnwrap(repository.inbox(id: id))
        inbox.relayDestinationID = "synthetic-destination"
        inbox.verificationStatus = .pending
        try repository.updateInbox(inbox)
        let capabilities = CapabilityStore(
            reachability: NetworkReachabilityMonitor(monitoringEnabled: false, initialSatisfied: true), defaults: defaults)
        TestLifetimeRetainer.retain(repository, session)
        return (repository, session, capabilities, try XCTUnwrap(repository.inbox(id: id)))
    }

    private func state(_ status: String) -> RelayAPIClient.DestinationState {
        .init(destinationId: "synthetic-destination", status: status, maskedEmail: nil, resendAfterSeconds: nil)
    }

    func testMaintenanceAndDisabledRefreshCanVerifyWithoutReopeningMutations() async throws {
        for mode in [CapabilityServiceMode.maintenance, .disabled] {
            let (repository, session, capabilities, inbox) = try fixture()
            capabilities.applyOperatorPolicy(.privateEmail, .init(mode: mode, retryAfter: nil))
            var begins = 0
            var checks = 0
            let expected = state("verified")
            let service = ForwardingInboxService(repository: repository, session: session, capabilities: capabilities,
                begin: { _ in begins += 1; return expected }, status: { destinationID in
                    XCTAssertEqual(destinationID, inbox.relayDestinationID)
                    checks += 1; return expected
                })
            _ = try await service.refresh(inbox)
            XCTAssertEqual(checks, 1)
            XCTAssertEqual(begins, 0, "GET never resends mail")
            XCTAssertEqual(repository.inbox(id: inbox.id)?.verificationStatus, .verified)
            XCTAssertEqual(capabilities.modes[.privateEmail], mode)
            XCTAssertNotEqual(capabilities.availability(.privateEmail, operation: .mutate), .available)
            do { _ = try await service.begin(inbox); XCTFail("Operator-blocked mutation admitted") }
            catch RelayService.Failure.capabilityBlocked(_, _) { }
            XCTAssertEqual(begins, 0)
        }
    }

    func testStatusResponseForChangedEmailGenerationCannotWriteVerification() async throws {
        let (repository, session, capabilities, inbox) = try fixture()
        let expected = state("verified")
        var continuation: CheckedContinuation<RelayAPIClient.DestinationState, Error>?
        let service = ForwardingInboxService(repository: repository, session: session, capabilities: capabilities,
            begin: { _ in XCTFail("Unexpected resend"); return expected }, status: { _ in
                try await withCheckedThrowingContinuation { continuation = $0 }
            })
        let check = Task { try await service.refresh(inbox) }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let suspended = try XCTUnwrap(continuation)
        var changed = try XCTUnwrap(repository.inbox(id: inbox.id))
        changed.email = "another@example.test"
        try repository.updateInbox(changed)
        suspended.resume(returning: expected)
        _ = try await check.value
        let live = try XCTUnwrap(repository.inbox(id: inbox.id))
        XCTAssertEqual(live.email, "another@example.test")
        XCTAssertEqual(live.verificationStatus, .unverified)
        XCTAssertNil(live.relayDestinationID)
        XCTAssertGreaterThan(live.verificationGeneration, inbox.verificationGeneration)
    }

    func testVaultLockDuringHalfOpenGETCancelsPersistenceAndReleasesAdmission() async throws {
        let (repository, session, capabilities, inbox) = try fixture()
        for _ in 0..<3 { capabilities.noteInfrastructureFailure(.privateEmail, now: .now.addingTimeInterval(-31)) }
        let expected = state("verified")
        var continuation: CheckedContinuation<RelayAPIClient.DestinationState, Error>?
        let service = ForwardingInboxService(repository: repository, session: session, capabilities: capabilities,
            begin: { _ in XCTFail("Unexpected resend"); return expected }, status: { _ in
                try await withCheckedThrowingContinuation { continuation = $0 }
            })
        let check = Task { try await service.refresh(inbox) }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let suspended = try XCTUnwrap(continuation)
        session.lock()
        suspended.resume(returning: expected)
        do { _ = try await check.value; XCTFail("Locked response persisted") } catch is CancellationError { }
        session.adoptUnlocked(key: [UInt8](repeating: 0x38, count: 32), publishSharedSession: false)
        repository.reload()
        XCTAssertEqual(repository.inbox(id: inbox.id)?.verificationStatus, .pending)
        XCTAssertEqual(capabilities.health[.privateEmail], .outage, "Lock has no remote health outcome")
        let next = try XCTUnwrap(capabilities.admitDestinationStatus())
        capabilities.finishDestinationStatus(next, outcome: .cancelled)
    }

    func testBeginDelegatesOnceAndSeparateStatusNeverCallsBegin() async throws {
        let (repository, session, capabilities, inbox) = try fixture()
        let pending = state("pending")
        var begins = 0
        var statuses = 0
        let service = ForwardingInboxService(repository: repository, session: session, capabilities: capabilities,
            begin: { live in XCTAssertEqual(live, inbox); begins += 1; return pending },
            status: { _ in statuses += 1; return pending })
        _ = try await service.begin(inbox)
        XCTAssertEqual(begins, 1)
        XCTAssertEqual(statuses, 0)
        _ = try await service.refresh(inbox)
        XCTAssertEqual(begins, 1)
        XCTAssertEqual(statuses, 1)
    }

    func testURLCancelledStatusDoesNotReportRemoteSuccessAndReleasesProbe() async throws {
        let (repository, session, capabilities, inbox) = try fixture()
        for _ in 0..<3 { capabilities.noteInfrastructureFailure(.privateEmail, now: .now.addingTimeInterval(-31)) }
        let expected = state("pending")
        let service = ForwardingInboxService(repository: repository, session: session, capabilities: capabilities,
            begin: { _ in XCTFail("Unexpected resend"); return expected },
            status: { _ in throw URLError(.cancelled) })
        do { _ = try await service.refresh(inbox); XCTFail("Expected cancellation") } catch is CancellationError { }
        XCTAssertEqual(repository.inbox(id: inbox.id)?.verificationStatus, .pending)
        XCTAssertEqual(capabilities.health[.privateEmail], .outage)
        let next = try XCTUnwrap(capabilities.admitDestinationStatus())
        capabilities.finishDestinationStatus(next, outcome: .cancelled)
    }
}
