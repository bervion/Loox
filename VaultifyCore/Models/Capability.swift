import Foundation

/// Optional network capabilities — services the app can live without. The Core
/// Vault (unlock, local items, Persona, Spaces, owned AutoFill) never depends
/// on any of these; each capability fails independently (INV-CAP-03/08).
nonisolated enum CapabilityID: String, Codable, Sendable, CaseIterable {
    case shareLink = "share_link"
    case privateEmail = "private_email"
    /// Short presentation links for Share Vault links. Deliberately its own
    /// capability: the shortener can be down while canonical share creation
    /// stays healthy, and a shorten failure must read as its own outage.
    case shortLink = "short_link"
    /// Loox Quick View — one-shot field-scoped browser handoff. Its own
    /// capability (distinct worker, distinct outage) so the feature can be
    /// gated independently via the signed manifest's `quick_view.exposure`.
    case quickView = "quick_view"
}

/// Operator-declared service mode — the BACKEND's vocabulary, verbatim (both
/// workers return it in `X-Loox-Service-State` / problem+json). The client
/// mirrors the backend's per-operation gate but can never widen it: the server
/// enforces authoritatively.
nonisolated enum CapabilityServiceMode: String, Codable, Sendable {
    case active, degraded, maintenance, disabled, retired
}

/// Runtime health observed by this device (distinct from operator mode —
/// INV-CAP-04: outage is not maintenance is not offline).
nonisolated enum CapabilityHealth: String, Codable, Sendable {
    case healthy, degraded, outage, unknown
}

nonisolated enum ConnectivityState: String, Sendable {
    case online, constrained, offline, unknown
}

/// Operation classes — the backend's gating vocabulary. `read` means viewing
/// LOCAL records and is never network-gated (INV-CAP-05/10).
nonisolated enum CapabilityOperation: String, Codable, Sendable {
    case read, create, mutate, delete, revoke
}

/// What a screen should render for one (capability, operation) pair.
/// Deliberately NOT a boolean (INV-CAP-08); each case maps to distinct copy.
nonisolated enum CapabilityAvailability: Equatable, Sendable {
    case available
    case offline                      // this device has no network
    case maintenance(retryAfter: Int?)
    case temporarilyUnavailable       // runtime outage / circuit open
    case disabledByOperator
    case disabledByUser               // preference off — never set by outages (INV-CAP-09)
    case retired                      // verified permanent (410/manifest only, INV-CAP-07)
    case unknown
}

/// Pure availability resolution — every screen goes through this, no scattered
/// per-screen `if`s. Order: local-read safety → user preference → verified
/// operator policy (with the backend-parity operation table) → connectivity →
/// circuit breaker → observed health.
nonisolated enum CapabilityResolver {

    /// Mirror of the backend's per-mode operation gate (loox-relay/loox-link
    /// `capability.ts`): growth stops first; privacy/safety ops (delete/revoke)
    /// and read stay usable through maintenance/disabled. Parity-tested; the
    /// server still enforces, so drift can only over-restrict, never bypass.
    static func operationEnabled(mode: CapabilityServiceMode, operation: CapabilityOperation) -> Bool {
        switch mode {
        case .active: return true
        case .degraded: return operation != .create
        case .maintenance, .disabled: return operation == .read || operation == .delete || operation == .revoke
        case .retired: return false
        }
    }

    static func availability(userPreference: Bool,
                             mode: CapabilityServiceMode,
                             health: CapabilityHealth,
                             connectivity: ConnectivityState,
                             breakerOpen: Bool,
                             retryAfter: Int? = nil,
                             operationDisabled: Bool = false,
                             operation: CapabilityOperation) -> CapabilityAvailability {
        // Local records are never hidden by any remote/preference state.
        if operation == .read { return .available }
        if !userPreference { return .disabledByUser }
        if mode == .retired { return .retired }
        // Manifest per-operation override narrows on top of the mode table —
        // it can only ever disable further, never re-enable past the gate.
        if operationDisabled || !operationEnabled(mode: mode, operation: operation) {
            switch mode {
            case .maintenance: return .maintenance(retryAfter: retryAfter)
            case .disabled: return .disabledByOperator
            default: return .temporarilyUnavailable
            }
        }
        if connectivity == .offline { return .offline }
        if breakerOpen { return .temporarilyUnavailable }
        if health == .outage { return .temporarilyUnavailable }
        return .available
    }
}

/// Per-capability circuit breaker (INV-CAP-03: one per service, never shared).
/// Counts ONLY infrastructure failures — timeout/DNS/reset/502/503/504 without
/// a structured capability code. 401/409/cap/validation and operator-state
/// 503s are the service WORKING, not failing. Value-type state machine so it
/// is deterministically testable with injected clocks.
nonisolated struct CapabilityCircuitBreaker: Sendable, Equatable {
    enum Phase: Equatable, Sendable {
        case closed
        case open(until: Date)
        case halfOpen            // one probe in flight
    }

    private(set) var phase: Phase = .closed
    /// Sliding window of the last 5 eligible outcomes (true = infra failure).
    private(set) var window: [Bool] = []
    /// Consecutive open cycles — drives 30s → 60s → 2m → 5m escalation.
    private(set) var openCycles: Int = 0
    private(set) var probeGeneration: UInt64 = 0

    private static let openDurations: [TimeInterval] = [30, 60, 120, 300]

    /// Whether a request may go out now. An expired `open` transitions to
    /// `halfOpen` and admits exactly ONE probe.
    mutating func allowRequest(now: Date = .now) -> Bool {
        switch phase {
        case .closed: return true
        case .open(let until):
            guard now >= until else { return false }
            phase = .halfOpen
            probeGeneration &+= 1
            return true
        case .halfOpen: return false
        }
    }

    /// A lifecycle cancellation is neither a service success nor a failure.
    /// Only the admitted probe's token can release that half-open slot.
    mutating func cancelProbe(generation: UInt64, now: Date = .now) {
        guard phase == .halfOpen, probeGeneration == generation else { return }
        phase = .open(until: now)
    }

    mutating func recordSuccess() {
        window.append(false)
        trim()
        phase = .closed
        openCycles = 0
    }

    mutating func recordInfrastructureFailure(now: Date = .now) {
        window.append(true)
        trim()
        if phase == .halfOpen {
            reopen(now: now)      // probe failed → escalate
            return
        }
        let failures = window.filter { $0 }.count
        let lastThreeAllFailed = window.count >= 3 && window.suffix(3).allSatisfy { $0 }
        let failureRate = window.isEmpty ? 0 : Double(failures) / Double(window.count)
        if lastThreeAllFailed || (window.count == 5 && failureRate >= 0.6) {
            reopen(now: now)
        }
    }

    var isOpen: Bool {
        if case .closed = phase { return false }
        return true
    }

    private mutating func reopen(now: Date) {
        let duration = Self.openDurations[min(openCycles, Self.openDurations.count - 1)]
        openCycles += 1
        phase = .open(until: now.addingTimeInterval(duration))
    }

    private mutating func trim() {
        if window.count > 5 { window.removeFirst(window.count - 5) }
    }
}
