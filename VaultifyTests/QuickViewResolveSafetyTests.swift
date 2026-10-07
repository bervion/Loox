import Foundation
import XCTest
@testable import Vaultify

@MainActor
final class QuickViewResolveSafetyTests: XCTestCase {
    private func fixture() throws -> (QuickViewApprovalFlowModel, CapabilityStore, QuickViewHistoryStore) {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "quick-view-resolve-\(UUID().uuidString)"))
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        let session = VaultSession(settings: settings, persistentKeyMaterialEnabled: false)
        session.adoptUnlocked(key: [UInt8](repeating: 0x33, count: 32), publishSharedSession: false)
        let repo = VaultRepository(store: VaultStore(inMemory: true), session: session, externalSideEffectsEnabled: false)
        repo.reload()
        try repo.add(VaultItem(id: "resolve-login", category: .login, title: "Synthetic login",
            fields: [DynamicField(label: "Username", kind: .username, value: "quality-user")]))
        let capabilities = CapabilityStore(
            reachability: NetworkReachabilityMonitor(monitoringEnabled: false, initialSatisfied: true), defaults: defaults)
        capabilities.applyQuickViewExposure(.ga)
        let history = QuickViewHistoryStore(persistenceEnabled: false)
        let flow = QuickViewApprovalFlowModel(itemID: "resolve-login", defaultSelectedFieldIDs: [],
            vaultSession: session, repository: repo, history: history, capabilities: capabilities)
        TestLifetimeRetainer.retain(repo, session)
        return (flow, capabilities, history)
    }

    func testCancelledHalfOpenResolveReleasesExactlyOneProbeWithoutOutageIncrement() async throws {
        for failure in [CancellationError() as Error, URLError(.cancelled) as Error] {
            let (flow, capabilities, history) = try fixture()
            let expired = Date().addingTimeInterval(-31)
            for _ in 0..<3 { capabilities.noteInfrastructureFailure(.quickView, now: expired) }
            var continuation: CheckedContinuation<QuickViewAPIClient.ResolvedSession, Error>?
            flow.resolveOverride = { _ in
                try await withCheckedThrowingContinuation { continuation = $0 }
            }
            let resolving = Task { await flow.resolve(code: "synthetic-locator") }
            for _ in 0..<100 where continuation == nil { await Task.yield() }
            let suspended = try XCTUnwrap(continuation, "Expired cooldown must admit resolve's one recovery probe")
            XCTAssertNil(capabilities.admitRequest(.quickView), "A simultaneous probe must be refused")
            flow.cancel()
            suspended.resume(throwing: failure)
            await resolving.value
            XCTAssertEqual(flow.state, .idle)
            XCTAssertEqual(history.rows.map(\.result), [.cancelled])
            XCTAssertEqual(capabilities.health[.quickView], .outage, "Cancellation supplies no new health outcome")
            XCTAssertEqual(capabilities.modes[.quickView], .active)
            let replacement = try XCTUnwrap(capabilities.admitRequest(.quickView), "Cancelled probe must release its slot")
            XCTAssertNil(capabilities.admitRequest(.quickView))
            capabilities.finishRequest(replacement, outcome: .cancelled)
            // Duplicate terminal delivery cannot cancel a subsequently admitted probe.
            let next = try XCTUnwrap(capabilities.admitRequest(.quickView))
            capabilities.finishRequest(replacement, outcome: .infrastructureFailure)
            XCTAssertNil(capabilities.admitRequest(.quickView))
            capabilities.finishRequest(next, outcome: .cancelled)
        }
    }

    func testLateServerErrorAfterCancelCannotReplaceIdleOrDuplicateHistory() async throws {
        let (flow, capabilities, history) = try fixture()
        var continuation: CheckedContinuation<QuickViewAPIClient.ResolvedSession, Error>?
        flow.resolveOverride = { _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        let resolving = Task { await flow.resolve(code: "synthetic-locator") }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let suspended = try XCTUnwrap(continuation)
        flow.cancel()
        suspended.resume(throwing: QuickViewAPIError.server(status: 504, code: nil))
        await resolving.value
        XCTAssertEqual(flow.state, .idle)
        XCTAssertEqual(history.rows.map(\.result), [.cancelled])
        XCTAssertEqual(capabilities.modes[.quickView], .active, "A transport failure must not invent an operator mode")
    }
}
