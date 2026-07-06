import Foundation

/// Pure lifecycle rules for aliases. Which states a user can reach, and which
/// transitions are allowed, both depend on whether the relay backend is live.
nonisolated enum AliasLifecycle {

    /// States a user can create/move an alias into. Without the relay, `active`
    /// and `paused` are unreachable (nothing forwards yet).
    static func userReachableStates(flag: Bool) -> [AliasStatus] {
        flag
            ? [.draft, .reserved, .active, .paused, .disabled]
            : [.draft, .reserved, .disabled]
    }

    /// Whether a status transition is permitted. Moving to a relay-only state
    /// (`active`/`paused`) is rejected while the relay is off.
    static func canTransition(from: AliasStatus, to: AliasStatus, flag: Bool) -> Bool {
        userReachableStates(flag: flag).contains(to)
    }
}
