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
        supports2FA(urls: item.urlField.map { [$0.value] } ?? [], title: item.title)
    }

    /// Raw-values variant for audit snapshots (items can carry multiple websites).
    /// Any confidently-matched host wins; title is only consulted when NO URL
    /// yields a host (same false-positive guard as the item overload).
    nonisolated static func supports2FA(urls: [String], title: String) -> Bool {
        let hosts = urls.compactMap { DomainNormalizer.host(from: $0) }
        if !hosts.isEmpty {
            if hosts.contains(where: { h in domains.contains { h == $0 || h.hasSuffix("." + $0) } }) {
                return true
            }
            // The richer curated dataset extends (never replaces) the legacy list.
            return ServiceCapabilityCatalog.capability(urls: urls)?.supportsTOTP == true
        }
        let title = title.lowercased()
        return titleFragments.contains { title.contains($0) }
    }

}
