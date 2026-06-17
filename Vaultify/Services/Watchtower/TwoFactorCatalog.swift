import Foundation

/// A conservative, curated set of popular services known to support 2FA (TOTP),
/// matched by item domain/URL (primary) or title (fallback). Only confident matches
/// — no false positives. Easy to extend by adding more entries.
///
/// Source authority: 2fa.directory — limited to well-known, widely-used services.
nonisolated enum TwoFactorCatalog {

    // MARK: - Catalog

    /// Registrable domains that confidently identify a 2FA-capable service.
    /// Matched against the URL's host by equality or subdomain suffix (not raw
    /// substring) so e.g. "x.com" can't false-match "netflix.com".
    private static let domains: [String] = [
        // Social / Communication
        "google.com", "gmail.com", "accounts.google",
        "facebook.com", "instagram.com", "twitter.com", "x.com",
        "linkedin.com", "discord.com", "slack.com", "telegram.org",
        "reddit.com", "snapchat.com", "tiktok.com", "pinterest.com",
        "whatsapp.com",

        // Email / Productivity
        "outlook.com", "hotmail.com", "live.com", "microsoft.com",
        "apple.com", "icloud.com",
        "yahoo.com",
        "zoho.com",
        "protonmail.com", "proton.me",

        // Cloud / Dev
        "github.com", "gitlab.com", "bitbucket.org",
        "amazon.com", "aws.amazon.com",
        "dropbox.com", "box.com", "onedrive.live.com",
        "notion.so", "atlassian.com", "jira.atlassian.com", "confluence.atlassian.com",
        "figma.com",
        "heroku.com", "vercel.com", "netlify.com", "cloudflare.com", "digitalocean.com",
        "npm.com", "npmjs.com",

        // Finance / Payment
        "paypal.com", "stripe.com", "coinbase.com", "binance.com",
        "robinhood.com", "etrade.com",

        // Security
        "1password.com", "lastpass.com", "bitwarden.com", "dashlane.com",
        "authy.com",

        // Shopping / Services
        "shopify.com", "ebay.com", "etsy.com",
        "uber.com", "lyft.com", "airbnb.com",
        "netflix.com", "spotify.com", "twitch.tv", "steam.com", "steampowered.com",
        "epicgames.com", "ea.com", "battle.net",

        // Vietnamese services
        "vietcombank.com.vn", "techcombank.com.vn", "mbbank.com.vn",
        "vpbank.com.vn", "bidv.com.vn", "agribank.com.vn",
        "momo.vn", "zalopay.vn", "shopeepay.vn",
    ]

    /// Title fragments for services where users commonly don't add a URL.
    private static let titleFragments: [String] = [
        "google", "facebook", "instagram", "twitter", "linkedin", "discord",
        "slack", "github", "gitlab", "microsoft", "apple", "icloud",
        "amazon", "dropbox", "paypal", "coinbase", "binance", "shopify",
        "netflix", "spotify", "steam", "twitch", "vietcombank", "techcombank",
        "mbbank", "vpbank", "momo",
    ]

    // MARK: - Matching

    /// Returns `true` if the item is confidently matched to a 2FA-supporting service.
    /// Host match on the URL is primary; title match is a conservative fallback.
    nonisolated static func supports2FA(_ item: VaultItem) -> Bool {
        if let host = host(from: item.urlField?.value) {
            return domains.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        // Only fall back to title when no URL is present (reduces false positives).
        let title = item.title.lowercased()
        return titleFragments.contains { title.contains($0) }
    }

    /// Lowercased host from a possibly scheme-less URL string (strips scheme, path,
    /// userinfo, and port). Returns nil for an empty/blank input.
    private static func host(from raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return nil }
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        return s.isEmpty ? nil : s
    }
}
