import Foundation

/// App/vault lifetime coordinator. Only visible consumers register inbox IDs;
/// no profile-wide scans or background polling. The clock and clients are
/// injectable so race, cancellation and request-budget tests need no network.
@MainActor @Observable final class DestinationVerificationCoordinator {
    nonisolated deinit {}

    nonisolated struct Identity: Hashable, Sendable {
        let inboxID: String
        let email: String
        let destinationID: String?
        let generation: UInt64
        init(_ inbox: ForwardingInbox) {
            inboxID = inbox.id; email = inbox.email
            destinationID = inbox.relayDestinationID; generation = inbox.verificationGeneration
        }
    }
    enum Failure: Error { case unavailable, throttled(seconds: Int) }
    private struct Flight {
        let token: UUID
        let identity: Identity
        let isBegin: Bool
        let task: Task<RelayAPIClient.DestinationState?, Error>
    }
    private let inboxes: () -> [ForwardingInbox]
    private let policy: () -> Bool
    private let beginRequest: (ForwardingInbox) async throws -> RelayAPIClient.DestinationState
    private let refreshRequest: (ForwardingInbox) async throws -> RelayAPIClient.DestinationState?
    private let now: () -> Date
    private let sleep: (TimeInterval) async throws -> Void
    private let jitter: () -> Double
    private var consumers: [UUID: Set<String>] = [:]
    private var priorityConsumers: Set<UUID> = []
    private var flights: [String: Flight] = [:]
    private var loop: Task<Void, Never>?
    private var active = false
    private var unlocked = false
    private var requestTimes: [Date] = []
    private var nextCheck: [Identity: Date] = [:]
    private var failures: [Identity: Int] = [:]
    private var globalRetryUntil: Date?
    private(set) var checkingInboxIDs: Set<String> = []
    private(set) var lastChecked: [String: Date] = [:]
    private(set) var errors: [String: String] = [:]
    let verification = ForwardingInboxVerification()

    init(inboxes: @escaping () -> [ForwardingInbox], policy: @escaping () -> Bool,
         begin: @escaping (ForwardingInbox) async throws -> RelayAPIClient.DestinationState,
         refresh: @escaping (ForwardingInbox) async throws -> RelayAPIClient.DestinationState?,
         now: @escaping () -> Date = Date.init,
         sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
         jitter: @escaping () -> Double = { Double.random(in: 0...0.2) }) {
        self.inboxes = inboxes; self.policy = policy
        beginRequest = begin; refreshRequest = refresh
        self.now = now; self.sleep = sleep; self.jitter = jitter
    }

    @discardableResult func register(_ inboxIDs: Set<String>, priority: Bool = false) -> UUID {
        let token = UUID()
        consumers[token] = inboxIDs
        if priority { priorityConsumers.insert(token) }
        wake(immediate: true)
        return token
    }
    func update(_ token: UUID, inboxIDs: Set<String>) {
        consumers[token] = inboxIDs
        wake(immediate: true)
    }
    func unregister(_ token: UUID) {
        consumers.removeValue(forKey: token)
        priorityConsumers.remove(token)
        wake()
    }
    func setLifecycle(active: Bool, unlocked: Bool) {
        let becameUsable = (!self.active || !self.unlocked) && active && unlocked
        self.active = active; self.unlocked = unlocked
        if !active || !unlocked {
            cancelFlights()
            loop?.cancel(); loop = nil
            if !unlocked {
                errors.removeAll(); lastChecked.removeAll()
                nextCheck.removeAll(); failures.removeAll()
                flights.removeAll()
                verification.clearSensitiveState()
            }
        } else {
            verification.resumeCountdown()
            wake(immediate: becameUsable)
        }
    }
    /// Repository and policy observation drive this even if pending begins
    /// after the old loop ended. Unchanged poll responses do not write storage.
    func stateChanged() { wake() }

    func begin(_ inbox: ForwardingInbox) async throws -> RelayAPIClient.DestinationState {
        guard canRefresh else { throw Failure.unavailable }
        while let previous = flights[inbox.id] {
            if previous.isBegin {
                guard let state = try await previous.task.value else { throw Failure.unavailable }
                return state
            }
            _ = try? await previous.task.value
            finishFlight(inbox.id, token: previous.token)
        }
        guard active, unlocked, let live = inboxes().first(where: { $0.id == inbox.id }),
              live.email == inbox.email, live.verificationGeneration == inbox.verificationGeneration else { throw CancellationError() }
        let identity = Identity(live)
        let token = UUID()
        let task = Task { () throws -> RelayAPIClient.DestinationState? in
            try Task.checkCancellation()
            return try await beginRequest(live)
        }
        flights[live.id] = Flight(token: token, identity: identity, isBegin: true, task: task)
        defer { finishFlight(live.id, token: token); wake(immediate: true) }
        guard let state = try await task.value else { throw Failure.unavailable }
        return state
    }

    @discardableResult func refreshNow(_ inbox: ForwardingInbox) async throws -> RelayAPIClient.DestinationState? {
        guard canRefresh else { throw Failure.unavailable }
        let identity = Identity(inbox)
        if let existing = flights[inbox.id] {
            if existing.identity == identity { return try await existing.task.value }
            _ = try? await existing.task.value
            finishFlight(inbox.id, token: existing.token)
        }
        guard canRefresh, let live = inboxes().first(where: { $0.id == inbox.id }),
              Identity(live) == identity, live.relayDestinationID != nil else { throw CancellationError() }
        let instant = now()
        if let until = globalRetryUntil, until > instant {
            throw Failure.throttled(seconds: Int(until.timeIntervalSince(instant).rounded(.up)))
        }
        if failures[identity] != nil, let until = nextCheck[identity], until > instant {
            throw Failure.throttled(seconds: Int(until.timeIntervalSince(instant).rounded(.up)))
        }
        requestTimes.removeAll { instant.timeIntervalSince($0) >= 60 }
        guard requestTimes.count < 30 else {
            throw Failure.throttled(seconds: max(1, Int((60 - instant.timeIntervalSince(requestTimes[0])).rounded(.up))))
        }
        requestTimes.append(instant)
        let token = UUID()
        let task = Task { () throws -> RelayAPIClient.DestinationState? in
            try Task.checkCancellation()
            return try await refreshRequest(live)
        }
        flights[live.id] = Flight(token: token, identity: identity, isBegin: false, task: task)
        checkingInboxIDs.insert(live.id)
        defer { finishFlight(live.id, token: token) }
        do {
            let result = try await task.value
            try Task.checkCancellation()
            guard canRefresh, inboxes().contains(where: { Identity($0) == identity }) else { throw CancellationError() }
            lastChecked[live.id] = now()
            errors.removeValue(forKey: live.id)
            failures.removeValue(forKey: identity)
            nextCheck[identity] = now().addingTimeInterval(8)
            return result
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            let count = (failures[identity] ?? 0) + 1
            failures[identity] = count
            var delay = min(60, 15 * pow(2, Double(min(count - 1, 2)))) * (1 + min(0.2, max(0, jitter())))
            if case RelayAPIClient.DestinationStatusFailure.throttled(let seconds) = error {
                delay = max(delay, Double(seconds))
                globalRetryUntil = now().addingTimeInterval(delay)
            } else if case RelayAPIClient.DestinationStatusFailure.retryLater(_, let seconds) = error {
                delay = max(delay, Double(seconds))
                globalRetryUntil = now().addingTimeInterval(delay)
            } else if case RelayAPIClient.Failure.capability(_, let retryAfter) = error, let retryAfter {
                delay = max(delay, Double(retryAfter))
                globalRetryUntil = now().addingTimeInterval(delay)
            }
            nextCheck[identity] = now().addingTimeInterval(delay)
            errors[live.id] = appString("Couldn’t check verification. Your saved status is unchanged.")
            throw error
        }
    }

    private var canRefresh: Bool { active && unlocked && policy() }
    private var visibleIDs: Set<String> { consumers.values.reduce(into: Set<String>()) { $0.formUnion($1) } }
    private func wake(immediate: Bool = false) {
        let visible = visibleIDs
        for (id, flight) in flights where !canRefresh || !inboxes().contains(where: { Identity($0) == flight.identity }) || !visible.contains(id) {
            flight.task.cancel()
            flights.removeValue(forKey: id)
            checkingInboxIDs.remove(id)
        }
        loop?.cancel(); loop = nil
        guard canRefresh else { return }
        let pending = inboxes().filter { visible.contains($0.id) && $0.verificationStatus == .pending && $0.relayDestinationID != nil }
        guard !pending.isEmpty else { return }
        if immediate {
            for inbox in pending where failures[Identity(inbox)] == nil { nextCheck.removeValue(forKey: Identity(inbox)) }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, canRefresh else { return }
                let visible = visibleIDs
                let priority = priorityConsumers.reduce(into: Set<String>()) { $0.formUnion(self.consumers[$1] ?? []) }
                let pending = inboxes().filter { visible.contains($0.id) && $0.verificationStatus == .pending && $0.relayDestinationID != nil }
                    .sorted { priority.contains($0.id) && !priority.contains($1.id) }
                guard !pending.isEmpty else { return }
                for inbox in pending where (nextCheck[Identity(inbox)] ?? .distantPast) <= now() {
                    guard !Task.isCancelled else { return }
                    _ = try? await refreshNow(inbox)
                    if case .pending = inbox.verificationStatus,
                       nextCheck[Identity(inbox)] == nil { nextCheck[Identity(inbox)] = now().addingTimeInterval(8) }
                }
                do { try await sleep(1) } catch { return }
            }
        }
    }
    private func cancelFlights() {
        for flight in flights.values { flight.task.cancel() }
        flights.removeAll()
        checkingInboxIDs.removeAll()
    }
    private func finishFlight(_ id: String, token: UUID) {
        guard flights[id]?.token == token else { return }
        flights.removeValue(forKey: id)
        checkingInboxIDs.remove(id)
    }
}
