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
        case .aliasCapReached: return .fail("alias_cap_reached")
        // Handled upstream (verified operator state, never retried); defensive here.
        case .capability: return .fail("capability")
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
        // Verified operator states — each is distinct from an outage and from
        // offline (INV-CAP-04); the vault itself is always unaffected.
        case .capabilityBlocked(.maintenance, _):
            return appString("Private Email is under maintenance. Creating or changing private addresses is temporarily paused. Your vault continues to work normally.")
        case .capabilityBlocked(.disabled, _):
            return appString("Private Email is currently unavailable. Loox has temporarily disabled this feature. Your vault and other features continue to work normally.")
        case .capabilityBlocked(.retired, _):
            return appString("Private Email is no longer offered by Loox. Your saved alias records remain visible so you can identify accounts that used them.")
        case .capabilityBlocked:
            return appString("We’re having trouble reaching the relay service. Your vault and saved passwords are not affected.")
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
        case .rejected("alias_cap_reached"):
            // Backend cap counts active + paused; permanent deletes free space.
            return appString("You’ve reached the limit for private addresses. Permanently delete addresses you no longer use.")
        case .principalUnavailable, .rejected:
            return appString("Check your connection and iCloud, then try again.")
        }
    }
}
