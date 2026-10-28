import Foundation

/// Codec for the `vaultify://membership` deep link, which opens the Loox hub
/// (plan, limits, upgrade). It is the deep link App Store Connect requires for
/// the Loox Membership In-App Event, so the event lands on the membership
/// content instead of the Home screen.
nonisolated enum LooxMembershipDeepLink {
    private static let scheme = "vaultify"
    private static let host = "membership"

    static let url = URL(string: "\(scheme)://\(host)")!

    /// True for `vaultify://membership`, with or without a trailing slash or
    /// query (App Store adds none today, but a future event parameter must not
    /// turn the link into a no-op).
    static func matches(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host else { return false }
        return url.path.isEmpty || url.path == "/"
    }
}
