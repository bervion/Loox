import Foundation

/// Single source of truth for optional-capability state (INV: no scattered
/// per-screen availability `if`s). Holds, per capability: the user preference,
/// the last VERIFIED operator mode (persisted — a relaunch mid-maintenance
/// renders the right state), observed runtime health, and an independent
/// circuit breaker. Connectivity is shared (device-level fact).
///
/// Nothing here is fetched at startup (INV-CAP-02): modes update from
/// structured backend responses (problem+json / 410) and from the non-blocking
/// screen-open health probe. A transport failure NEVER changes the operator
/// mode (INV-CAP-07) and NEVER flips the user preference (INV-CAP-09).
@MainActor @Observable final class CapabilityStore {

    /// Structured operator signal parsed from a backend response.
    nonisolated struct OperatorSignal: Sendable, Equatable {
        let mode: CapabilityServiceMode
        let retryAfter: Int?
    }

    private let defaults: UserDefaults
    private let reachability: NetworkReachabilityMonitor

    private(set) var modes: [CapabilityID: CapabilityServiceMode] = [:]
    private(set) var retryAfters: [CapabilityID: Int] = [:]
    private(set) var health: [CapabilityID: CapabilityHealth] = [:]
    private var breakers: [CapabilityID: CapabilityCircuitBreaker] = [:]
    /// Manifest per-operation overrides (narrow-only) + localized-copy keys.
    /// Session-scoped: re-applied when the cached manifest re-verifies.
    private(set) var disabledOperations: [CapabilityID: Set<CapabilityOperation>] = [:]
    private(set) var messageKeys: [CapabilityID: String] = [:]
    /// Verified schema-2+ Quick View exposure (DEC-QV-EXPOSURE-01) — nil when
    /// no manifest has verified yet, or it predates schema 2 / omits the
    /// field. Session-scoped like the other manifest-derived state above.
    private(set) var quickViewExposure: QuickViewExposure?

    init(reachability: NetworkReachabilityMonitor, defaults: UserDefaults = .standard) {
        self.reachability = reachability
        self.defaults = defaults
        for id in CapabilityID.allCases {
            modes[id] = persistedMode(id) ?? .active   // bundled default: active
            health[id] = .unknown
            breakers[id] = CapabilityCircuitBreaker()
        }
    }

    // MARK: User preference (independent axis — INV-CAP-09)

    func userPreference(_ id: CapabilityID) -> Bool {
        defaults.object(forKey: prefKey(id)) as? Bool ?? true
    }

    func setUserPreference(_ id: CapabilityID, enabled: Bool) {
        defaults.set(enabled, forKey: prefKey(id))
    }

    // MARK: Resolution

    var connectivity: ConnectivityState {
        reachability.hasSatisfiedNetworkPath ? .online : .offline
    }

    func availability(_ id: CapabilityID, operation: CapabilityOperation) -> CapabilityAvailability {
        CapabilityResolver.availability(userPreference: userPreference(id),
                                        mode: modes[id] ?? .active,
                                        health: health[id] ?? .unknown,
                                        connectivity: connectivity,
                                        breakerOpen: breakers[id]?.isOpen ?? false,
                                        retryAfter: retryAfters[id],
                                        operationDisabled: disabledOperations[id]?.contains(operation) ?? false,
                                        operation: operation)
    }

    /// Breaker admission gate — call before a network request for `id`.
    func allowRequest(_ id: CapabilityID, now: Date = .now) -> Bool {
        breakers[id]?.allowRequest(now: now) ?? true
    }

    // MARK: Outcome reporting (the ONLY inputs that move state)

    func noteSuccess(_ id: CapabilityID) {
        breakers[id]?.recordSuccess()
        health[id] = .healthy
        setMode(id, .active, retryAfter: nil)
    }

    /// Infra failure (timeout/DNS/reset/plain 502-504): breaker + health only —
    /// the operator mode is NOT touched (a Cloudflare outage isn't maintenance,
    /// and never retirement — INV-CAP-07).
    func noteInfrastructureFailure(_ id: CapabilityID, now: Date = .now) {
        breakers[id]?.recordInfrastructureFailure(now: now)
        health[id] = .outage
    }

    /// Structured operator state (problem+json `capability_*` / 410): verified
    /// signal → persist. The service answered, so it isn't an outage; breakers
    /// don't count it.
    func noteOperatorSignal(_ id: CapabilityID, _ signal: OperatorSignal) {
        health[id] = .healthy
        setMode(id, signal.mode, retryAfter: signal.retryAfter)
    }

    /// Non-outcome failures (401, 409s, caps, validation): the service is up.
    func noteServiceResponded(_ id: CapabilityID) {
        breakers[id]?.recordSuccess()
        health[id] = .healthy
    }

    /// Operator policy from a VERIFIED manifest — policy distribution only:
    /// unlike a live response it says nothing about runtime health, so the
    /// breaker and health are deliberately untouched. Carries the manifest's
    /// narrow-only per-operation overrides and the localized-copy key.
    func applyOperatorPolicy(_ id: CapabilityID, _ signal: OperatorSignal,
                             disabledOps: Set<CapabilityOperation> = [],
                             messageKey: String? = nil) {
        disabledOperations[id] = disabledOps
        messageKeys[id] = messageKey
        setMode(id, signal.mode, retryAfter: signal.retryAfter)
    }

    /// Verified schema-2+ exposure for Quick View, applied per manifest
    /// (nil clears it — a schema-1 or field-omitting manifest carries no
    /// signal, which must NOT be confused with a signed "hidden").
    func applyQuickViewExposure(_ exposure: QuickViewExposure?) {
        quickViewExposure = exposure
    }

    // MARK: Persistence (operator mode survives relaunch — never the health)

    private func setMode(_ id: CapabilityID, _ mode: CapabilityServiceMode, retryAfter: Int?) {
        modes[id] = mode
        retryAfters[id] = retryAfter
        defaults.set(mode.rawValue, forKey: modeKey(id))
        // Reduced App Group snapshot for the extension (INV-CAP-06: the
        // extension never fetches capability state itself).
        CapabilitySnapshot.write(modes: modes)
    }

    private func persistedMode(_ id: CapabilityID) -> CapabilityServiceMode? {
        (defaults.string(forKey: modeKey(id))).flatMap(CapabilityServiceMode.init(rawValue:))
    }

    private func prefKey(_ id: CapabilityID) -> String { "capability_pref_\(id.rawValue)" }
    private func modeKey(_ id: CapabilityID) -> String { "capability_mode_\(id.rawValue)" }
}
