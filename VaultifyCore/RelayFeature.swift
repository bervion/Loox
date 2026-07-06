import Foundation

/// Gates the email-relay ("private email") capability. The relay backend does
/// not exist yet, so live/`active` aliases are kept unreachable — a persona can
/// draft and reserve an alias, but nothing renders a working `name@domain`
/// address until this flips on. Shipping an address that looks live before the
/// relay works would be a user-trust breach (and an App Review risk). The model
/// carries the full lifecycle; this flag decides how much of it is reachable.
nonisolated enum RelayFeature {
    /// When false, `.active`/`.paused` aliases can't be created and no address is
    /// ever rendered with an `@domain` suffix.
    static let activeAliasesEnabled = false
}
