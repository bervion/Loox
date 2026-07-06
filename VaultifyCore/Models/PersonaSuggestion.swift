import Foundation

/// One candidate username/email for a new login, tagged with the persona it came
/// from so isolation can be decided purely. `sourcePersonaID == nil` means the
/// global/default identity (not owned by any persona) — which a strictAnonymous
/// persona excludes alongside every other persona's data.
nonisolated struct UsernameCandidate: Equatable, Sendable {
    /// Lower number = preferred source. Pinned raw values so ordering is explicit.
    enum Source: Int, Equatable, Sendable {
        case activePersonaProfile = 0
        case defaultIdentity = 1
        case recent = 2
    }
    var value: String
    var sourcePersonaID: String?
    var source: Source
    var lastUsedAt: Date?
}

/// Pure username-suggestion policy for the active persona. The single place the
/// isolation rule lives, shared by the app and the AutoFill extension (DRY).
nonisolated enum PersonaUsernameSuggester {

    /// Ordered, de-duplicated suggestions for the active persona.
    ///
    /// - `strictAnonymous`: HARD-EXCLUDE every candidate whose `sourcePersonaID`
    ///   is not exactly the active persona (including `nil` / the global default).
    ///   This is exclusion, never a down-rank (INV-R03).
    /// - `isolated`: keep all candidates but always rank the active persona's own
    ///   ahead of others.
    /// - `standard`: own persona, then default identity, then recents by recency.
    static func suggestions(candidates: [UsernameCandidate],
                            activePersonaID: String,
                            policy: PersonaIsolationPolicy) -> [String] {
        let filtered = candidates.filter { candidate in
            guard !candidate.value.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            if policy == .strictAnonymous {
                return candidate.sourcePersonaID == activePersonaID
            }
            return true
        }

        let ranked = filtered.sorted { lhs, rhs in
            let lhsOwn = lhs.sourcePersonaID == activePersonaID ? 0 : 1
            let rhsOwn = rhs.sourcePersonaID == activePersonaID ? 0 : 1
            if lhsOwn != rhsOwn { return lhsOwn < rhsOwn }
            if lhs.source != rhs.source { return lhs.source.rawValue < rhs.source.rawValue }
            // More recently used first (nil = oldest).
            return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
        }

        // De-duplicate case-insensitively, keeping the best-ranked occurrence.
        var seen: Set<String> = []
        var out: [String] = []
        for candidate in ranked {
            let key = candidate.value.lowercased()
            if seen.insert(key).inserted { out.append(candidate.value) }
        }
        return out
    }
}
