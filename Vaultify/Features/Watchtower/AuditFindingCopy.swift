import Foundation

/// Localized copy for findings, keyed by ruleID. Wording contracts live here:
/// never "2FA is off" / "Passkey is disabled" (Loox cannot know server-side
/// state) — always "not saved in Loox". No "!", no em-dash in user copy.
nonisolated enum AuditFindingCopy {

    static func title(ruleID: String) -> LocalizedStringResource {
        let base: LocalizedStringResource = switch ruleID {
        case "exposure.leaked": "Passwords found in known leaks"
        case "quality.weak": "Weak passwords"
        case "quality.contains-context": "Passwords that include account details"
        case "reuse.exact": "Reused passwords"
        case "auth.totp-missing": "Verification codes available"
        case "auth.passkey-available": "Passkeys available"
        case "integrity.duplicate-exact": "Duplicate items"
        case "integrity.duplicate-conflict": "Conflicting logins"
        case "integrity.otp-invalid": "Broken verification codes"
        case "integrity.incomplete": "Logins without a credential"
        case "url.malformed": "Websites that cannot be read"
        case "url.insecure-http": "Websites using http"
        case "url.punycode": "Websites with unusual characters"
        case "url.ip-login": "Websites using an IP address"
        case "maintenance.stale": "Long-unreviewed items"
        case "maintenance.missing-url": "Logins without a website"
        case "maintenance.missing-username": "Logins without a username"
        case "maintenance.missing-metadata": "Logins missing details"
        default: "Review suggested"
        }
        return base.inAppLocalized
    }

    /// Title for ONE item's copy of a finding (the item detail warning banner).
    /// `title(ruleID:)` is a report heading and speaks in groups ("Reused
    /// passwords"); on a single item that reads as someone else's summary.
    /// Rules with no item-scoped wording fall back to the report heading.
    static func itemTitle(ruleID: String) -> LocalizedStringResource {
        let base: LocalizedStringResource? = switch ruleID {
        case "exposure.leaked": "Password found in a known leak"
        case "reuse.exact": "Password reused on other items"
        case "auth.totp-missing": "Verification code available"
        default: nil
        }
        guard let base else { return title(ruleID: ruleID) }
        return base.inAppLocalized
    }

    static func explanation(ruleID: String) -> LocalizedStringResource {
        let base: LocalizedStringResource = switch ruleID {
        case "exposure.leaked":
            "This password appears in a known leaked-password dataset. Anyone can try leaked passwords first."
        case "quality.weak":
            "This password follows patterns that cracking tools try early, such as common words, dates, or keyboard rows."
        case "quality.contains-context":
            "This password contains details saved with the account, such as the username or website. Anyone targeting this account could guess it."
        case "reuse.exact":
            "These accounts share one password. A breach of any one of them could put the others at risk."
        case "auth.totp-missing":
            "This site supports verification codes, but no code is saved in Loox for this account."
        case "auth.passkey-available":
            "This site supports passkeys, but Loox does not currently have one saved for this account."
        case "integrity.duplicate-exact":
            "These items are identical copies, usually left over from an import."
        case "integrity.duplicate-conflict":
            "These items use the same site and username but different passwords. One of them is likely out of date."
        case "integrity.otp-invalid":
            "The saved one-time code secret cannot produce a code. Signing in with it would fail."
        case "integrity.incomplete":
            "This login has no password, passkey, or verification code saved."
        case "url.insecure-http":
            "The saved website address uses http, which sends data unencrypted."
        case "url.punycode":
            "The website address contains unusual characters that can imitate another site. Worth a quick review."
        case "url.ip-login":
            "The website address is a raw IP address. If this is not intentional, review it."
        case "url.malformed":
            "The saved website address could not be read as a valid link."
        case "maintenance.stale":
            "This item has not been reviewed in years. A quick check keeps it trustworthy."
        case "maintenance.missing-metadata":
            "AutoFill matches logins to apps and sites by the website address, and the username tells similar accounts apart. Add the missing details so this login fills reliably."
        default:
            "This item could use a quick review."
        }
        return base.inAppLocalized
    }

    /// Stage label for the Running screen (rules grouped into readable stages).
    static func stageTitle(ruleID: String) -> LocalizedStringResource {
        let base: LocalizedStringResource = switch ruleID {
        case let id where id.hasPrefix("quality"): "Password quality"
        case let id where id.hasPrefix("reuse"): "Password reuse"
        case let id where id.hasPrefix("exposure"): "Known leaks"
        case let id where id.hasPrefix("auth"): "Authentication options"
        default: "Vault cleanup"
        }
        return base.inAppLocalized
    }
}
