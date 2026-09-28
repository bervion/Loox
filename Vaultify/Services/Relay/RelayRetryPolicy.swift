import Foundation
import CloudKit

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
        // Both defensive here: RelayService intercepts refresh-required with
        // its own attach-then-fresh-nonce loop before the policy runs, and
        // quota maps to the upsell surface once purchases are live.
        case .entitlementRefreshRequired: return .fail("entitlement_refresh_required")
        case .quotaExceeded: return .fail("quota_exceeded")
        // Global ceiling, deliberately answered — same "try again later" lane
        // as rate_limited, never the infrastructure/server_5xx lane.
        case .capacityReached: return .fail("capacity_reached")
        // Consent gate, not an outage — surface the re-confirm copy, never retry.
        case .destinationNotVerified: return .fail("destination_not_verified")
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
    static func principalFailure(for error: any Error) -> Self {
        if let cloudError = error as? CKError, cloudError.code == .notAuthenticated {
            return .iCloudAuthenticationRequired
        }
        // Loaded fine but sealed by another vault: telling the user to check
        // iCloud here sent them after a problem that did not exist.
        if RelayPrincipalEscrowService.isUnopenableWithThisVault(error) {
            return .principalFromAnotherVault
        }
        return .principalUnavailable
    }

    /// Whether the alert for this failure offers the deliberate "Reset Private
    /// Email" recovery. Only a principal this vault can never open qualifies.
    var offersPrivateEmailReset: Bool { self == .principalFromAnotherVault }

    /// Headline for a relay failure. Every screen used to title these alerts
    /// "Couldn’t reach the relay" whatever went wrong, so a consent gate, an
    /// announced maintenance window and a locked vault all announced themselves
    /// as a connection problem — and the one sentence that told the user what to
    /// actually do sat under a heading that contradicted it.
    var userTitle: String {
        switch self {
        case .capabilityBlocked(.maintenance, _):
            return appString("Under maintenance")
        case .capabilityBlocked(.disabled, _):
            return appString("Temporarily unavailable")
        case .capabilityBlocked(.retired, _):
            return appString("No longer offered")
        case .vaultLocked:
            return appString("Loox is locked")
        case .missingDestination:
            return appString("Add an email first")
        case .network:
            return appString("You’re offline")
        case .rejected("unauthorized"):
            return appString("Couldn’t verify this device")
        case .rejected("destination_not_verified"):
            return appString("Confirm your forwarding email")
        case .rejected("rate_limited"), .rejected("capacity_reached"):
            return appString("Too many requests")
        case .rejected("alias_cap_reached"):
            return appString("Address limit reached")
        case .iCloudAuthenticationRequired:
            return appString("Sign in to iCloud")
        case .principalUnavailable:
            return appString("Couldn’t access iCloud for Private Email")
        case .principalFromAnotherVault:
            return appString("Private Email was set up with another vault")
        case .capabilityBlocked, .rejected:
            return appString("Couldn’t reach the relay")
        }
    }

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
            return appString("Add an email to this identity’s profile. That’s where your aliases forward to.")
        case .network:
            return appString("You’re offline. Connect to the internet to change this private address.")
        case .rejected("unauthorized"):
            return appString("Couldn’t verify this device. Unlock Loox and try again.")
        case .rejected("destination_not_verified"):
            // Consent gate (DEC-DST-01), not an outage — point the user at the
            // confirm flow instead of "check your connection".
            return appString("Confirm your forwarding email before using this private address. Open Forwarding inboxes and tap “Confirm email”.")
        case .rejected("rate_limited"), .rejected("capacity_reached"):
            // capacity_reached = a global ceiling (innocent user) — same gentle
            // "later" copy; the vault and existing forwarding are unaffected.
            return appString("Too many requests. Please try again shortly.")
        case .rejected("alias_cap_reached"):
            // Backend cap counts active + paused; permanent deletes free space.
            return appString("You’ve reached the limit for private addresses. Permanently delete addresses you no longer use.")
        case .iCloudAuthenticationRequired:
            return appString("Private Email needs an authenticated iCloud account. Check your iCloud sign-in in Settings, then try again. Vault sync can stay off.")
        case .principalUnavailable:
            return appString("Loox couldn’t load your Private Email identity from iCloud. Check your iCloud account in iPhone Settings and try again. You don’t need to enable vault sync. If this continues, contact support.")
        case .principalFromAnotherVault:
            return appString("The vault on this device can’t open it, usually because Loox was reinstalled. If the original vault is still on another device, restore it here instead. Otherwise, reset Private Email. Addresses you made before keep forwarding, but you won’t be able to manage them here.")
        case .rejected:
            return appString("Check your connection and iCloud, then try again.")
        }
    }
}
