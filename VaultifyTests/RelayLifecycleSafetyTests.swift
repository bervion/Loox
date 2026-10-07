import XCTest
import CloudKit
@testable import Vaultify

@MainActor
final class RelayLifecycleSafetyTests: XCTestCase {
    private func fixture(status: AliasStatus = .disabled, minted: Bool = true) throws -> (VaultRepository, VaultSession, RelayService, EmailAlias) {
        let defaults = UserDefaults(suiteName: "relay-lifecycle-\(UUID().uuidString)")!
        let session = VaultSession(settings: SettingsStore(defaults: defaults, mirrorToSharedConfig: false),
                                   persistentKeyMaterialEnabled: false)
        session.adoptUnlocked(key: [UInt8](repeating: 0x2b, count: 32), publishSharedSession: false)
        let repository = VaultRepository(store: VaultStore(inMemory: true), session: session,
                                         externalSideEffectsEnabled: false)
        repository.reload()
        TestLifetimeRetainer.retain(repository)
        let persona = try XCTUnwrap(repository.activePersona)
        let inboxID = try repository.addManualInbox(email: "fixture@example.test")
        var verified = try XCTUnwrap(repository.inbox(id: inboxID))
        verified.verificationStatus = .verified
        verified.relayDestinationID = "fixture-destination"
        try repository.updateInbox(verified)
        try repository.setDefaultInbox(verified)
        let id = try repository.createPerSiteAlias(for: persona, boundItemId: nil)
        if minted { try repository.markMinted(try XCTUnwrap(repository.aliases.first { $0.id == id })) }
        try repository.setAliasStatus(try XCTUnwrap(repository.aliases.first { $0.id == id }), to: status)
        let alias = try XCTUnwrap(repository.aliases.first { $0.id == id })
        let service = RelayService(repository: repository, session: session)
        return (repository, session, service, alias)
    }

    func testUnboundInitialMintCheckpointsBeforeRouteFailureAndRetryNeverDuplicatesAddress() async throws {
        let (repository, _, service, alias) = try fixture(status: .reserved, minted: false)
        XCTAssertNil(alias.boundItemId)
        XCTAssertFalse(alias.backendMinted)
        var commands: [RelayService.CommandRequest] = []
        var failedFirstRoute = false
        service.commandOverride = { request in
            commands.append(request)
            if request.kind == .rotateDestination && !failedFirstRoute {
                failedFirstRoute = true
                throw RelayAPIClient.Failure.transport
            }
            return Data()
        }

        do { try await service.activate(alias); XCTFail("Expected first route failure") }
        catch { XCTAssertEqual(error as? RelayAPIClient.Failure, .transport) }
        let checkpoint = try XCTUnwrap(repository.aliases.first { $0.id == alias.id })
        XCTAssertTrue(checkpoint.backendMinted, "Create acknowledgment must survive a later route failure")
        XCTAssertEqual(checkpoint.status, .reserved)
        XCTAssertNil(checkpoint.boundItemId, "An owned Login must not be required for initial issuance")
        XCTAssertEqual(checkpoint.localPart, alias.localPart)

        try await service.activate(checkpoint)
        XCTAssertEqual(commands.map(\.kind), [.createAlias, .rotateDestination, .rotateDestination])
        XCTAssertEqual(commands.map(\.aliasID), [alias.localPart, alias.localPart, alias.localPart])
        let live = try XCTUnwrap(repository.aliases.first { $0.id == alias.id })
        XCTAssertEqual(live.localPart, alias.localPart)
        XCTAssertTrue(live.backendMinted)
        XCTAssertNil(live.boundItemId)
        XCTAssertEqual(live.status, .active)
        XCTAssertEqual(repository.aliases.count, 1)
    }

    func testResumeRoutesThenReactivatesSameOwnedNamespaceWithoutRemint() async throws {
        for status in [AliasStatus.paused, .disabled] {
            let (repository, _, service, alias) = try fixture(status: status)
            var commands: [RelayService.CommandRequest] = []
            service.commandOverride = { request in
                commands.append(request)
                // The local row remains paused until the create acknowledgment.
                XCTAssertEqual(repository.aliases.first { $0.id == alias.id }?.status, status)
                return Data()
            }
            try await service.activate(alias)
            XCTAssertEqual(commands.map(\.kind), [.rotateDestination, .createAlias])
            XCTAssertEqual(commands.map(\.aliasID), [alias.localPart, alias.localPart])
            XCTAssertNil(commands.first?.domainID, "Legacy mutation namespace stays byte-compatible")
            XCTAssertEqual(commands.last?.domainID, alias.relayDomainID, "Resume create signs the exact namespace")
            XCTAssertEqual(commands.first?.path, "/v1/relay/aliases/\(alias.localPart)/destination")
            XCTAssertEqual(commands.last?.path, "/v1/relay/aliases")
            let live = try XCTUnwrap(repository.aliases.first { $0.id == alias.id })
            XCTAssertEqual(live.localPart, alias.localPart)
            XCTAssertEqual(live.relayDomainID, alias.relayDomainID)
            XCTAssertEqual(live.status, .active)
            XCTAssertNil(live.disabledAt)
        }
    }

    func testResumeRefusalNeverRemintsOrClaimsActive() async throws {
        for failure in [RelayAPIClient.Failure.aliasExists, .server(403)] {
            let (repository, _, service, alias) = try fixture()
            var commands: [RelayService.CommandRequest] = []
            service.commandOverride = { request in
                commands.append(request)
                if request.kind == .createAlias { throw failure }
                return Data()
            }
            do { try await service.activate(alias); XCTFail("Expected resume rejection") }
            catch { XCTAssertEqual(error as? RelayAPIClient.Failure, failure) }
            XCTAssertEqual(commands.map(\.kind), [.rotateDestination, .createAlias])
            XCTAssertEqual(commands.map(\.aliasID), [alias.localPart, alias.localPart])
            let live = try XCTUnwrap(repository.aliases.first { $0.id == alias.id })
            XCTAssertEqual(live.status, .disabled)
            XCTAssertEqual(live.localPart, alias.localPart)
            XCTAssertEqual(repository.aliases.count, 1)
        }
    }

    func testFailedRouteDoesNotAttemptResumeAndKeepsPaused() async throws {
        let (repository, _, service, alias) = try fixture(status: .paused)
        var commands: [RelayService.CommandRequest] = []
        service.commandOverride = { request in commands.append(request); throw RelayAPIClient.Failure.transport }
        do { try await service.activate(alias); XCTFail("Expected route failure") }
        catch { XCTAssertEqual(error as? RelayAPIClient.Failure, .transport) }
        XCTAssertEqual(commands.map(\.kind), [.rotateDestination])
        XCTAssertEqual(repository.aliases.first { $0.id == alias.id }?.status, .paused)
    }

    private func halfOpenCapabilities() -> CapabilityStore {
        let defaults = UserDefaults(suiteName: "relay-breaker-\(UUID().uuidString)")!
        let capabilities = CapabilityStore(
            reachability: NetworkReachabilityMonitor(monitoringEnabled: false, initialSatisfied: true), defaults: defaults)
        let expired = Date().addingTimeInterval(-31)
        for _ in 0..<3 { capabilities.noteInfrastructureFailure(.privateEmail, now: expired) }
        return capabilities
    }

    func testEscrowCancellationReleasesHalfOpenProbeWithoutPrincipalOrOutageMapping() async throws {
        let (repository, _, service, _) = try fixture()
        let capabilities = halfOpenCapabilities()
        service.capabilities = capabilities
        let inbox = try XCTUnwrap(repository.forwardingInboxes.first)
        service.principalOverride = { _ in throw CancellationError() }
        do { _ = try await service.beginDestinationVerification(inbox); XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(capabilities.health[.privateEmail], .outage, "Cancellation adds no health result")
        let probe = try XCTUnwrap(capabilities.admitRelayCommand(now: Date().addingTimeInterval(1)))
        capabilities.finishRelayCommand(probe, outcome: .cancelled)
    }

    func testAttestationURLCancellationReleasesProbeAndPreservesOperatorMode() async throws {
        let (repository, _, service, _) = try fixture()
        let capabilities = halfOpenCapabilities()
        capabilities.applyOperatorPolicy(.privateEmail, .init(mode: .degraded, retryAfter: nil))
        service.capabilities = capabilities
        service.principalOverride = { _ in RelayPrincipalIdentity.generate() }
        service.assertionOverride = { _ in throw URLError(.cancelled) }
        do {
            _ = try await service.beginDestinationVerification(try XCTUnwrap(repository.forwardingInboxes.first))
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(capabilities.modes[.privateEmail], .degraded)
        let probe = try XCTUnwrap(capabilities.admitRelayCommand(now: Date().addingTimeInterval(1)))
        capabilities.finishRelayCommand(probe, outcome: .cancelled)
    }

    func testCancelledTransportCannotStrandProbeOrIncrementOutageCycle() async throws {
        let (repository, _, service, _) = try fixture()
        let capabilities = halfOpenCapabilities()
        service.capabilities = capabilities
        service.commandOverride = { _ in throw URLError(.cancelled) }
        do {
            _ = try await service.beginDestinationVerification(try XCTUnwrap(repository.forwardingInboxes.first))
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
        let now = Date().addingTimeInterval(1)
        let token = try XCTUnwrap(capabilities.admitRelayCommand(now: now))
        capabilities.finishRelayCommand(token, outcome: .cancelled, now: now)
        capabilities.finishRelayCommand(token, outcome: .infrastructureFailure, now: now)
        // A duplicate terminal call must not escalate/reopen for 60 seconds.
        let next = try XCTUnwrap(capabilities.admitRelayCommand(now: now))
        capabilities.finishRelayCommand(next, outcome: .responded, now: now)
        XCTAssertEqual(capabilities.health[.privateEmail], .healthy)
    }

    func testLocalEscrowFailureReleasesProbeWithoutPretendingRelayFailed() async throws {
        let (repository, _, service, _) = try fixture()
        let capabilities = halfOpenCapabilities()
        service.capabilities = capabilities
        service.principalOverride = { _ in throw CKError(.notAuthenticated) }
        do {
            _ = try await service.beginDestinationVerification(try XCTUnwrap(repository.forwardingInboxes.first))
            XCTFail("Expected iCloud authentication failure")
        } catch { XCTAssertEqual(error as? RelayService.Failure, .iCloudAuthenticationRequired) }
        let token = try XCTUnwrap(capabilities.admitRelayCommand(now: Date().addingTimeInterval(1)))
        capabilities.finishRelayCommand(token, outcome: .cancelled)
    }
}
