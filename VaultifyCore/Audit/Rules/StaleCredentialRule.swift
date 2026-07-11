import Foundation

/// Long-unreviewed credentials. INFO ONLY by design: NIST does not recommend
/// forced periodic rotation, so age alone is never an "issue" — the finding
/// invites a review, and only ever appears in the Maintain group. Items with an
/// explicit rotation cadence are handled by RotationStatus, not here.
nonisolated struct StaleCredentialRule: nonisolated AuditRule {
    let id = "maintenance.stale"
    let version = 1
    let category = AuditCategory.maintenance

    /// "Not reviewed in 4 years" (proposal Module F copy).
    private static let staleAfterDays = 4 * 365

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        snapshot.activeItems.compactMap { item in
            guard item.hasPassword, item.rotateDays == 0 else { return nil }
            let baseline = item.passwordChangedAt ?? item.createdAt
            let days = Calendar.current.dateComponents([.day], from: baseline, to: context.now).day ?? 0
            guard days >= Self.staleAfterDays else { return nil }
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                severity: .info,
                category: category,
                affectedItemIDs: [item.id],
                fingerprint: AuditFingerprint.make(ruleID: id, version: version, itemIDs: [item.id]),
                titleKey: "finding.maintenance.stale.title",
                detail: appString("Not reviewed in \(days / 365) years"),
                remediation: .reviewItem,
                estimatedFixSeconds: AuditFixEstimate.reviewItem,
                detectedAt: context.now)
        }
    }
}
