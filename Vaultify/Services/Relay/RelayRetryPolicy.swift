import Foundation

/// Pure decision table for relay-command failures: which failures earn ONE
/// silent rebuild-and-retry (fresh nonce + issued_at, re-signed), which need an
/// epoch refresh first, and which surface to the user. Bounded by `attempt` so
/// signed requests can never tight-loop.
nonisolated enum RelayRetryPolicy {
    enum Action: Equatable {
        /// Rebuild the command (fresh nonce/issued_at) and try once more.
        case retry
        /// Drop the principal cache, re-read the escrow, re-sign, try once more.
        case refreshEpochThenRetry
        /// Give up with a mapped reason (drives user-facing copy).
        case fail(String)
    }

    static func action(for failure: RelayAPIClient.Failure, attempt: Int) -> Action {
        switch failure {
        case .nonceReplay:
            return attempt == 1 ? .retry : .fail("nonce_replay")
        case .epochStale:
            return attempt == 1 ? .refreshEpochThenRetry : .fail("epoch_stale")
        case .unauthorized: return .fail("unauthorized")
        case .rateLimited:  return .fail("rate_limited")
        case .aliasExists:  return .fail("alias_exists")   // mint loop handles upstream
        case .transport:    return .fail("network")
        case .server(let code): return .fail("server_\(code)")
        }
    }
}

extension RelayService.Failure {
    /// Human copy for a relay failure — backend vocabulary (nonce/epoch) never
    /// reaches the user; those are auto-retried before ever landing here.
    var userMessage: String {
        switch self {
        case .vaultLocked:
            return appString("Unlock Loox and try again.")
        case .missingDestination:
            return appString("Add an email to this identity’s profile — that’s where your aliases forward to.")
        case .network:
            return appString("You’re offline. Connect to the internet to change this private address.")
        case .rejected("unauthorized"):
            return appString("Couldn’t verify this device. Unlock Loox and try again.")
        case .rejected("rate_limited"):
            return appString("Too many requests. Please try again shortly.")
        case .principalUnavailable, .rejected:
            return appString("Check your connection and iCloud, then try again.")
        }
    }
}
