import Foundation

/// What a known service supports, as curated data (2fa.directory /
/// passkeys.directory derived) — never inferred at runtime. `supportsPasskey`
/// means the SITE offers passkeys; whether the user saved one anywhere is
/// unknowable, so all copy must say "not saved in Loox", never "disabled".
nonisolated struct ServiceCapability: Codable, Sendable {
    let domain: String
    let supportsTOTP: Bool
    let supportsPasskey: Bool
    let securitySettingsURL: String?
}

/// Versioned curated capability dataset. Ships with the app (bump `version`
/// with every data change — it participates in finding fingerprints, so
/// updated data automatically re-surfaces affected findings for review).
nonisolated enum ServiceCapabilityCatalog {

    static let version = 1

    /// Fingerprint marker for rules driven by this dataset.
    static var fingerprintMarker: String { "capability-catalog-v\(version)" }

    /// Best match for any of an item's website URLs (registrable-suffix match,
    /// same false-positive guard as `TwoFactorCatalog`).
    static func capability(urls: [String]) -> ServiceCapability? {
        for raw in urls {
            guard let host = DomainNormalizer.host(from: raw) else { continue }
            // Longest suffix wins deterministically: "aws.amazon.com" must hit
            // its own entry, not fall through to "amazon.com" by hash order.
            let hit = byDomain
                .filter { host == $0.key || host.hasSuffix("." + $0.key) }
                .max { $0.key.count < $1.key.count }
            if let hit { return hit.value }
        }
        return nil
    }

    private static let byDomain: [String: ServiceCapability] = Dictionary(
        uniqueKeysWithValues: services.map { ($0.domain, $0) })

    // swiftlint:disable line_length
    static let services: [ServiceCapability] = [
        // Email / identity anchors
        .init(domain: "google.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://myaccount.google.com/security"),
        .init(domain: "gmail.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://myaccount.google.com/security"),
        .init(domain: "apple.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://account.apple.com/account/manage"),
        .init(domain: "icloud.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://account.apple.com/account/manage"),
        .init(domain: "microsoft.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://account.microsoft.com/security"),
        .init(domain: "outlook.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://account.microsoft.com/security"),
        .init(domain: "hotmail.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://account.microsoft.com/security"),
        .init(domain: "live.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://account.microsoft.com/security"),
        .init(domain: "yahoo.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://login.yahoo.com/account/security"),
        .init(domain: "proton.me", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: "https://account.proton.me/u/0/mail/account-password"),
        .init(domain: "protonmail.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: "https://account.proton.me/u/0/mail/account-password"),
        .init(domain: "zoho.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://accounts.zoho.com/home#security"),

        // Social / communication
        .init(domain: "facebook.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://accountscenter.facebook.com/password_and_security"),
        .init(domain: "instagram.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://accountscenter.instagram.com/password_and_security"),
        .init(domain: "whatsapp.com", supportsTOTP: false, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "x.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://x.com/settings/security"),
        .init(domain: "twitter.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://x.com/settings/security"),
        .init(domain: "linkedin.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://www.linkedin.com/mypreferences/d/categories/sign-in-and-security"),
        .init(domain: "tiktok.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "discord.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "slack.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "telegram.org", supportsTOTP: false, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "reddit.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: "https://www.reddit.com/settings/account"),
        .init(domain: "snapchat.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "pinterest.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),

        // Cloud / dev
        .init(domain: "github.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://github.com/settings/security"),
        .init(domain: "gitlab.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://gitlab.com/-/user_settings/authentication_log"),
        .init(domain: "bitbucket.org", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "amazon.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://www.amazon.com/a/settings/approval"),
        .init(domain: "aws.amazon.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "dropbox.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: "https://www.dropbox.com/account/security"),
        .init(domain: "box.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "notion.so", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "atlassian.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "figma.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "heroku.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "vercel.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "netlify.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "cloudflare.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: "https://dash.cloudflare.com/profile/authentication"),
        .init(domain: "digitalocean.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "npmjs.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),

        // Finance / payment
        .init(domain: "paypal.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://www.paypal.com/myaccount/security"),
        .init(domain: "stripe.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "coinbase.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: "https://accounts.coinbase.com/security"),
        .init(domain: "binance.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "robinhood.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "wise.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "etrade.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),

        // Security tools
        .init(domain: "1password.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "bitwarden.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "dashlane.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "lastpass.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),

        // Shopping / services / entertainment
        .init(domain: "shopify.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "ebay.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "etsy.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "uber.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "lyft.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "airbnb.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "netflix.com", supportsTOTP: false, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "spotify.com", supportsTOTP: false, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "twitch.tv", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "steampowered.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "epicgames.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "ea.com", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "battle.net", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "playstation.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "nintendo.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),
        .init(domain: "adobe.com", supportsTOTP: true, supportsPasskey: true, securitySettingsURL: nil),

        // Vietnamese services
        .init(domain: "vietcombank.com.vn", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "techcombank.com.vn", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "mbbank.com.vn", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "vpbank.com.vn", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "bidv.com.vn", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "agribank.com.vn", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "momo.vn", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
        .init(domain: "zalopay.vn", supportsTOTP: true, supportsPasskey: false, securitySettingsURL: nil),
    ]
    // swiftlint:enable line_length
}
