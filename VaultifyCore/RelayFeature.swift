import Foundation

/// Gates the email-relay ("private email") capability. The relay backend is
/// LIVE (receive-only forwarding on relay.looxpassword.com), so active aliases
/// are enabled: an activated alias renders its full working address. If the
/// backend ever has to be pulled, flipping this off makes every alias render as
/// a bare reserved local-part again — nothing looks live that isn't.
nonisolated enum RelayFeature {
    /// When false, `.active`/`.paused` aliases can't be created and no address is
    /// ever rendered with an `@domain` suffix.
    static let activeAliasesEnabled = true
}
