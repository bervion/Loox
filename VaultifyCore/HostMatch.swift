import Foundation

/// The ONE host-match rule for every fill surface — the OS AutoFill list,
/// QuickType promotion, and the Safari popup: exact host, or a parent/child on
/// a full label boundary. Nothing looser. A substring clause here is a phishing
/// vector: it promotes real credentials on `evilgoogle.com` or
/// `google.com.evil.io`, lending the page legitimacy with the vault's own data.
nonisolated enum HostMatch {
    /// Whether two hosts belong to the same site under the label-boundary rule.
    /// Symmetric: `related(page, stored) == related(stored, page)`.
    static func related(_ first: String, _ second: String) -> Bool {
        let a = normalized(first), b = normalized(second)
        guard !a.isEmpty, !b.isEmpty else { return false }
        // An IP literal has no label hierarchy — parent/child never applies.
        if isIPLiteral(a) || isIPLiteral(b) { return a == b }
        return a == b || a.hasSuffix(".\(b)") || b.hasSuffix(".\(a)")
    }

    /// Lowercased, trimmed, and stripped of the FQDN trailing dot, so
    /// `Login.Example.com.` and `login.example.com` compare equal.
    static func normalized(_ host: String) -> String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if h.hasSuffix(".") { h.removeLast() }
        return h
    }

    private static func isIPLiteral(_ host: String) -> Bool {
        if host.contains(":") { return true }  // colons never appear in DNS names → IPv6
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
}
