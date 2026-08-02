import Foundation

/// Logins with no way to sign in at all: no password, no passkey, no one-time
/// code. Usually an aborted save or a lossy import.
nonisolated struct IncompleteItemRule: nonisolated AuditRule {
    let id = "integrity.incomplete"
    let version = 1
    let category = AuditCategory.integrity

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        snapshot.activeItems.compactMap { item in
            guard item.loginHygieneEligible, !item.hasPassword, !item.hasPasskey, !item.hasTOTP
            else { return nil }
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                severity: .low,
                category: category,
                affectedItemIDs: [item.id],
                fingerprint: AuditFingerprint.make(ruleID: id, version: version, itemIDs: [item.id]),
                titleKey: "finding.integrity.incomplete.title",
                detail: nil,
                remediation: .fixData,
                estimatedFixSeconds: AuditFixEstimate.reviewItem,
                detectedAt: context.now)
        }
    }
}

/// Logins missing plumbing that AutoFill and audits depend on: a website URL
/// (per-host matching) or a username. Informational — the login still works.
nonisolated struct MissingMetadataRule: nonisolated AuditRule {
    let id = "maintenance.missing-metadata"
    let version = 1
    let category = AuditCategory.maintenance

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        snapshot.activeItems.compactMap { item in
            guard item.loginHygieneEligible, item.hasPassword else { return nil }
            let missingURL = item.rawURLs.allSatisfy(\.isEmpty)
            let missingUsername = item.usernames.allSatisfy(\.isEmpty)
            guard missingURL || missingUsername else { return nil }
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                severity: .info,
                category: category,
                affectedItemIDs: [item.id],
                fingerprint: AuditFingerprint.make(ruleID: id, version: version, itemIDs: [item.id]),
                titleKey: missingURL
                    ? "finding.maintenance.missing-url.title"
                    : "finding.maintenance.missing-username.title",
                detail: nil,
                remediation: .fixData,
                estimatedFixSeconds: AuditFixEstimate.reviewItem,
                detectedAt: context.now)
        }
    }
}
