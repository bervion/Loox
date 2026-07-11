import Foundation

/// Groups items sharing the exact same password. One finding PER GROUP (not per
/// item): the remediation — make each account unique — spans the whole group,
/// and per-group findings keep the fix queue and score penalties group-based.
nonisolated struct PasswordReuseRule: nonisolated AuditRule {
    let id = "reuse.exact"
    let version = 1
    let category = AuditCategory.reuse

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        var groups: [String: [VaultAuditItem]] = [:]
        for item in snapshot.activeItems {
            guard let password = item.password, !password.isEmpty else { continue }
            groups[password, default: []].append(item)
        }

        return groups.compactMap { password, members in
            guard members.count > 1 else { return nil }
            let ids = members.map(\.id).sorted()
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                // A 2-item overlap is common after imports; 3+ is a real blast radius.
                severity: members.count >= 3 ? .high : .medium,
                category: category,
                affectedItemIDs: ids,
                // The secret marker makes the fingerprint follow the GROUP identity:
                // changing the shared password resolves this finding naturally.
                fingerprint: AuditFingerprint.make(
                    ruleID: id, version: version, itemIDs: ids,
                    marker: AuditFingerprint.secretMarker(password, key: context.secretMarkerKey)),
                titleKey: "finding.reuse.exact.title",
                detail: appString("Used by \(members.count) items"),
                remediation: .changePassword,
                estimatedFixSeconds: AuditFixEstimate.replaceReusedPassword * (members.count - 1),
                detectedAt: context.now)
        }
        .sorted { $0.affectedItemIDs.count > $1.affectedItemIDs.count }
    }
}
