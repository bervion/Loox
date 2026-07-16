import Foundation
import StoreKit

/// The app-side billing identity: a random UUID set as StoreKit's
/// `appAccountToken` on every purchase — the backend's
/// `subscription_account_id` (handoff §1). Independent of email, persona,
/// alias, vault content and device by construction. Restore on another device
/// ADOPTS the token found inside that device's own verified transaction, so
/// every install converges on the purchase's identity (iCloud Keychain sync
/// stays out of scope in V1 by decision).
nonisolated enum LooxSubscriptionAccountToken {
    private static let account = "loox-subscription-account-token"

    static func stored() -> UUID? {
        guard let data = try? KeychainStore.get(account: account),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return UUID(uuidString: string)
    }

    static func loadOrCreate() -> UUID {
        if let existing = stored() { return existing }
        let fresh = UUID()
        try? KeychainStore.set(Data(fresh.uuidString.utf8), account: account)
        return fresh
    }

    /// Restore path: converge on the token the purchase actually carries.
    static func adopt(_ token: UUID) {
        try? KeychainStore.set(Data(token.uuidString.utf8), account: account)
    }
}

/// Static seams the service clients read (assigned once by `AppEnvironment`) —
/// keeps relay/link/quick-view free of any direct subscription dependency.
/// Write-once at startup from the main actor, read from request paths.
nonisolated enum LooxEntitlementClientHooks {
    /// Lease/grant payload for one service ("relay" | "link" | "quickview");
    /// nil = nothing to send (Free, dark, or no attach yet).
    nonisolated(unsafe) static var payloadProvider: (@Sendable (String) async -> [String: String]?)?
    /// `entitlement_refresh_required` recovery: re-attach (single-flight) and
    /// report whether the caller should retry its request once.
    nonisolated(unsafe) static var refreshHandler: (@Sendable () async -> Bool)?
}

/// Publishes the relay principal's WIRE identity (standard base64 WITH
/// padding — exactly the `principal_id` string `RelayAPIClient` sends and
/// exactly what the backend hashes for `relay_principal` bindings).
/// `RelayService` stamps it whenever it holds the principal; empty until the
/// relay has been used at least once, in which case attach simply omits the
/// relay binding and picks it up on a later trigger.
nonisolated enum RelayPrincipalWireIdentity {
    nonisolated(unsafe) static var currentB64: String?
}

/// B3 attach orchestration (dormant): owns the grant/lease state, runs the
/// four attach triggers from the handoff (§2) with single-flight + backoff,
/// and feeds the client hooks. Nothing here surfaces UI — purchases stay dark
/// for App Store users and the backend enforces nothing yet
/// (`ENTITLEMENT_MODE=off`); this exists so coverage telemetry and the
/// grant/lease plumbing are already true when enforcement turns on.
@MainActor @Observable final class LooxEntitlementCoordinator {
    private struct Lease: Codable {
        let value: String
        let expiresAtMs: Int64
    }

    private(set) var environment: String?
    private var leases: [String: Lease] = [:]
    /// One-shot grants held in MEMORY until replaced by a newer attach —
    /// resending the same grant is idempotent server-side (§3), so surviving
    /// a failed mutation matters more than forgetting after first use.
    private var grants: [String: String] = [:]

    @ObservationIgnored private var inFlight: Task<Bool, Never>?
    @ObservationIgnored private var noStateStrikes = 0

    /// Production leases may persist locally (never synced); Sandbox leases
    /// are MEMORY-ONLY per contract (§1) — TestFlight re-attaches often by design.
    private static let leaseAccount = "loox-entitlement-leases-production"

    init() {
        if let data = try? KeychainStore.get(account: Self.leaseAccount),
           let decoded = try? JSONDecoder().decode([String: Lease].self, from: data) {
            leases = decoded
            environment = "Production"
        }
    }

    // MARK: Client-hook surface

    /// Lease (unexpired) + pending grant for a service. An expired lease
    /// lazily kicks a re-attach (single-flight) instead of polling (§2).
    func payload(for service: String) -> [String: String]? {
        var out: [String: String] = [:]
        if let lease = leases[service] {
            if lease.expiresAtMs > Int64(Date.now.timeIntervalSince1970 * 1000) {
                out["lease"] = lease.value
            } else {
                Task { await attachNow() }
            }
        }
        if let grant = grants[service] { out["grant"] = grant }
        return out.isEmpty ? nil : out
    }

    /// `entitlement_refresh_required` → one re-attach; the caller retries once.
    func refreshAndReport() async -> Bool {
        await attachNow()
    }

    // MARK: Attach triggers

    /// Purchase/renewal success, restore, refresh-required, lease expiry —
    /// all funnel here. Single-flight; retryable failures back off inside the
    /// task; permanent failures give up silently (next trigger tries again).
    @discardableResult
    func attachNow() async -> Bool {
        if let running = inFlight { return await running.value }
        let task = Task<Bool, Never> { await performAttach() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func performAttach() async -> Bool {
        // Newest verified Loox subscription transaction carries the JWS the
        // backend verifies AND the appAccountToken this install converges on.
        guard let (jws, token) = await latestVerifiedTransaction() else { return false }
        if let token, LooxSubscriptionAccountToken.stored() == nil {
            LooxSubscriptionAccountToken.adopt(token)
        }

        let bindings = requestedBindings()
        var attempt = 0
        while true {
            do {
                let response = try await LooxEntitlementAttachClient.attach(
                    transactionJWS: jws, bindings: bindings)
                apply(response)
                noStateStrikes = 0
                return true
            } catch let error as LooxAttachError {
                switch error {
                case .retryable, .noSubscriptionState:
                    if error == .noSubscriptionState {
                        noStateStrikes += 1
                        // Recurrence = a backend bug to report, not a retry
                        // loop (handoff §4 answer 2).
                        if noStateStrikes >= 3 { return false }
                    }
                    attempt += 1
                    guard attempt < 3 else { return false }
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 4_000_000_000)
                case .tokenMissing, .unknownProduct, .verificationFailed, .transport, .server:
                    return false
                }
            } catch { return false }
        }
    }

    private func apply(_ response: LooxAttachResponse) {
        environment = response.environment
        for auth in response.authorizations {
            guard auth.error == nil else { continue }  // binding_conflict → B4 support flow
            if let lease = auth.lease, let expiry = auth.leaseExpiresAtMs {
                leases[auth.service] = Lease(value: lease, expiresAtMs: expiry)
            }
            if let grant = auth.grant {
                grants[auth.service] = grant
            } else if auth.bindingRequired == false {
                grants[auth.service] = nil  // bound — retire any stale grant
            }
        }
        persistLeasesIfProduction()
    }

    private func persistLeasesIfProduction() {
        guard environment == "Production" else {
            KeychainStore.delete(account: Self.leaseAccount)
            return
        }
        if let data = try? JSONEncoder().encode(leases) {
            try? KeychainStore.set(data, account: Self.leaseAccount)
        }
    }

    // MARK: Inputs

    /// Canonical identity strings → binding requests (subset is fine; an
    /// identity that doesn't exist yet joins on a later trigger).
    private func requestedBindings() -> [LooxAttachBindingRequest] {
        var bindings: [LooxAttachBindingRequest] = []
        if let relay = RelayPrincipalWireIdentity.currentB64 {
            bindings.append(.init(service: "relay", bindingType: "relay_principal",
                                  bindingValueHash: LooxBindingHash.hex(relay)))
        }
        if let link = LooxLinkAttestation.storedKeyId {
            bindings.append(.init(service: "link", bindingType: "attest_key_link",
                                  bindingValueHash: LooxBindingHash.hex(link)))
        }
        if let qv = QuickViewAttestation.storedKeyId {
            bindings.append(.init(service: "quickview", bindingType: "attest_key_qv",
                                  bindingValueHash: LooxBindingHash.hex(qv)))
        }
        return bindings
    }

    /// The highest-tier verified Loox transaction: its `jwsRepresentation`
    /// (what attach verifies) and its `appAccountToken` (restore adoption).
    private func latestVerifiedTransaction() async -> (String, UUID?)? {
        var best: (LooxTier, String, UUID?)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  let tier = LooxProductID.tier(for: transaction.productID) else { continue }
            if best == nil || tier > best!.0 {
                best = (tier, result.jwsRepresentation, transaction.appAccountToken)
            }
        }
        guard let best else { return nil }
        return (best.1, best.2)
    }
}
