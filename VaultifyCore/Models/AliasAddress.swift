import Foundation

/// Renders the selected address independently of forwarding activation.
/// Status badges communicate whether it can receive mail.
nonisolated enum AliasAddress {

    /// Keep the selected domain visible before verification and while paused.
    /// The pre-relay feature flag still suppresses addresses for disabled builds.
    static func display(localPart: String, status: AliasStatus,
                        relayDomain: String, flag: Bool = RelayFeature.activeAliasesEnabled) -> String {
        guard flag else { return localPart }
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
