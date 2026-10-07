import Foundation

/// Read-only ownership checks have their own policy and terminal breaker
/// outcome. They never widen the operator's mutation policy or send email.
@MainActor final class ForwardingInboxService {
    nonisolated deinit {}
    private let repository: VaultRepository
    private let session: VaultSession
    private let capabilities: CapabilityStore
    private let beginRequest: (ForwardingInbox) async throws -> RelayAPIClient.DestinationState
    private let statusRequest: (String) async throws -> RelayAPIClient.DestinationState

    init(repository: VaultRepository, session: VaultSession, capabilities: CapabilityStore,
         begin: @escaping (ForwardingInbox) async throws -> RelayAPIClient.DestinationState,
         status: @escaping (String) async throws -> RelayAPIClient.DestinationState = { try await RelayAPIClient.destinationStatus(id: $0) }) {
        self.repository = repository
        self.session = session
        self.capabilities = capabilities
        self.beginRequest = begin
        self.statusRequest = status
    }

    func begin(_ snapshot: ForwardingInbox) async throws -> RelayAPIClient.DestinationState {
        guard session.state == .unlocked else { throw RelayService.Failure.vaultLocked }
        guard capabilities.availability(.privateEmail, operation: .mutate) == .available else {
            throw RelayService.Failure.capabilityBlocked(capabilities.modes[.privateEmail] ?? .active,
                                                        retryAfter: capabilities.retryAfters[.privateEmail])
        }
        guard let live = repository.inbox(id: snapshot.id), live.email == snapshot.email,
              live.verificationGeneration == snapshot.verificationGeneration else { throw CancellationError() }
        return try await beginRequest(live)
    }

    func refresh(_ snapshot: ForwardingInbox) async throws -> RelayAPIClient.DestinationState? {
        guard let id = snapshot.relayDestinationID else { return nil }
        guard session.state == .unlocked, let token = capabilities.admitDestinationStatus() else {
            throw CancellationError()
        }
        let vaultKey = session.vaultKey?.bytes
        var outcome: CapabilityStore.RemoteStatusOutcome = .cancelled
        defer { capabilities.finishDestinationStatus(token, outcome: outcome) }
        do {
            let state = try await statusRequest(id)
            try Task.checkCancellation()
            guard session.state == .unlocked, session.vaultKey?.bytes == vaultKey else { throw CancellationError() }
            outcome = .responded
            _ = try repository.applyDestinationState(state, snapshot: snapshot, allowDestinationChange: false)
            return state
        } catch {
            if error is CancellationError || Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if case RelayAPIClient.DestinationStatusFailure.retryLater(let code, _) = error {
                outcome = (500...599).contains(code) ? .infrastructureFailure : .responded
            } else if let failure = error as? RelayAPIClient.Failure {
                switch failure {
                case .transport: outcome = .infrastructureFailure
                case .server(let code) where (500...599).contains(code): outcome = .infrastructureFailure
                case .capability(let mode, let retryAfter):
                    outcome = .operatorSignal(.init(mode: mode, retryAfter: retryAfter))
                default: outcome = .responded
                }
            } else { outcome = .responded }
            throw error
        }
    }
}
