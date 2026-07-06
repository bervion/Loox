import Foundation

/// Renders an alias address and mints local-parts. The ONLY place a full
/// `local@domain` address is ever produced — and only when the relay is live and
/// the alias is active, so no surface can show a working-looking address before
/// the backend exists.
nonisolated enum AliasAddress {

    /// The user-facing address. Pre-relay (or any non-active alias) this is just
    /// the bare local-part — never `@domain`, which would imply a live address.
    static func display(localPart: String, status: AliasStatus,
                        relayDomain: String, flag: Bool = RelayFeature.activeAliasesEnabled) -> String {
        guard flag, status == .active else { return localPart }
        return "\(localPart)@\(relayDomain)"
    }

    /// A random 12-char base32 local-part. No site/persona input, so per-site
    /// aliases can't be correlated back to a domain or identity.
    static func randomLocalPart() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var rng = SystemRandomNumberGenerator()
        return String((0..<12).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }
}
