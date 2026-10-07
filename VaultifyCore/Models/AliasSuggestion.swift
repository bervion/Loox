import Foundation

/// Pure ranking of a persona's aliases for a login context (create/edit login,
/// AutoFill). Candidates MUST already be scoped to one persona by the caller —
/// this ranks, it never widens (a strictAnonymous context therefore can't leak
/// another persona's addresses through here).
nonisolated enum AliasSuggestion {

    /// Conservative service-domain match: exact host or subdomain relationship,
    /// in either direction. Deliberately NOT eTLD+1 truncation — collapsing
    /// "login.example.co.uk" to two labels would wrongly equate unrelated
    /// "co.uk" sites; keeping full hosts and matching by dot-suffix never
    /// crosses a registrable boundary.
    static func relatedHosts(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased(), y = b.lowercased()
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x == y || x.hasSuffix(".\(y)") || y.hasSuffix(".\(x)")
    }

    /// Reuse priority: exact item binding → same-service domain → reusable
    /// persona addresses. Only live (active) aliases are usable as an address;
    /// gone entirely while the relay flag is off.
    static func ranked(aliases: [EmailAlias], itemID: String?, host: String?, flag: Bool, canonicalAddress: String? = nil) -> [EmailAlias] {
        guard flag else { return [] }
        var exact: [EmailAlias] = [], domain: [EmailAlias] = [], reusable: [EmailAlias] = []
        for alias in aliases where alias.status == .active && alias.resolvedAddress != nil {
            if (canonicalAddress != nil && alias.resolvedAddress == canonicalAddress)
                || (itemID != nil && alias.boundItemId == itemID) {
                exact.append(alias)
            } else if let host, let bound = alias.boundDomain, relatedHosts(bound, host) {
                domain.append(alias)
            } else if alias.tier == .persona {
                reusable.append(alias)
            }
        }
        return exact + domain + reusable
    }
}
