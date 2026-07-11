import Foundation

/// Shared host extraction/normalization for audit rules and catalogs.
nonisolated enum DomainNormalizer {

    /// Lowercased host from a possibly scheme-less URL string (strips scheme,
    /// path, userinfo, and port). Returns nil for an empty/blank input.
    static func host(from raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else {
            return nil
        }
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        return s.isEmpty ? nil : s
    }

    /// Host without a leading "www." — the display/grouping form.
    static func normalizedHost(from raw: String?) -> String? {
        guard let h = host(from: raw) else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}
