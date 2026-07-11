import Foundation

/// Exact duplicates: items that agree on normalized title, usernames, password,
/// and website set — the classic post-import leftover. One finding per group.
nonisolated struct ExactDuplicateRule: nonisolated AuditRule {
    let id = "integrity.duplicate-exact"
    let version = 1
    let category = AuditCategory.integrity

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        var groups: [String: [VaultAuditItem]] = [:]
        for item in snapshot.activeItems where item.hasPassword {
            let key = [
                item.title.lowercased().trimmingCharacters(in: .whitespaces),
                item.usernames.map { $0.lowercased() }.sorted().joined(separator: ","),
                item.password ?? "",
                item.rawURLs.compactMap { DomainNormalizer.normalizedHost(from: $0) }
                    .sorted().joined(separator: ","),
            ].joined(separator: "|")
            groups[key, default: []].append(item)
        }

        return groups.compactMap { key, members in
            guard members.count > 1 else { return nil }
            let ids = members.map(\.id).sorted()
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                severity: .low,
                category: category,
                affectedItemIDs: ids,
                fingerprint: AuditFingerprint.make(
                    ruleID: id, version: version, itemIDs: ids,
                    marker: AuditFingerprint.secretMarker(key, key: context.secretMarkerKey)),
                titleKey: "finding.integrity.duplicate-exact.title",
                detail: appString("\(members.count) identical copies"),
                remediation: .removeDuplicate,
                estimatedFixSeconds: AuditFixEstimate.removeDuplicate * (members.count - 1),
                detectedAt: context.now)
        }
    }
}

/// Conflicting duplicates: same site + same username but DIFFERENT passwords —
/// one of them is stale and will fail a login. Never auto-deleted; the UI shows
/// both with their update times and lets the user decide.
nonisolated struct ConflictingLoginRule: nonisolated AuditRule {
    let id = "integrity.duplicate-conflict"
    let version = 1
    let category = AuditCategory.integrity

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        var groups: [String: [VaultAuditItem]] = [:]
        for item in snapshot.activeItems where item.category == .login && item.hasPassword {
            let hosts = item.rawURLs.compactMap { DomainNormalizer.normalizedHost(from: $0) }
            guard let host = hosts.first else { continue }
            for username in item.usernames.map({ $0.lowercased() }) where !username.isEmpty {
                groups["\(host)|\(username)", default: []].append(item)
            }
        }

        var seen: Set<String> = []
        return groups.compactMap { _, members in
            let passwords = Set(members.map { $0.password ?? "" })
            guard members.count > 1, passwords.count > 1 else { return nil }
            let ids = members.map(\.id).sorted()
            // The same item pair can surface under several usernames — dedupe.
            let dedupeKey = ids.joined(separator: ",")
            guard seen.insert(dedupeKey).inserted else { return nil }
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                severity: .high,
                category: category,
                affectedItemIDs: ids,
                fingerprint: AuditFingerprint.make(ruleID: id, version: version, itemIDs: ids),
                titleKey: "finding.integrity.duplicate-conflict.title",
                detail: appString("\(members.count) items disagree on the password"),
                remediation: .reviewItem,
                estimatedFixSeconds: AuditFixEstimate.reviewItem * members.count,
                detectedAt: context.now)
        }
    }
}
