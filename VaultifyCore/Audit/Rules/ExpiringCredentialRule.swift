import Foundation

/// Field-level expiry tracking for credentials that genuinely expire —
/// signing certificates, provisioning profiles, API tokens with a recorded
/// end date. Expiry is LOCAL knowledge (a stored date), never a live provider
/// status; the copy must not imply revocation checking. Findings carry day
/// counts only — no filenames, providers, or identifying metadata.
nonisolated struct ExpiringCredentialRule: AuditRule {
    let id = "maintenance.expiring"
    let version = 1
    let category = AuditCategory.maintenance

    /// Attention window before the recorded end date.
    private static let warnWithinDays = 30

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        // Explicit result type: without it, the Safari target (which compiles
        // this file without SWIFT_APPROACHABLE_CONCURRENCY) infers the closure
        // as non-optional and rejects the guard's `nil`.
        snapshot.activeItems.compactMap { item -> AuditFinding? in
            guard let expiry = item.earliestExpiry else { return nil }
            let days = Calendar.current.dateComponents([.day], from: context.now, to: expiry).day ?? 0
            let expired = expiry <= context.now
            guard expired || days <= Self.warnWithinDays else { return nil }
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                severity: expired ? .medium : .info,
                category: category,
                affectedItemIDs: [item.id],
                fingerprint: AuditFingerprint.make(ruleID: id, version: version, itemIDs: [item.id]),
                titleKey: "finding.maintenance.expiring.title",
                detail: expired
                    ? appString("Recorded end date has passed")
                    : appString("Expires in \(max(days, 0)) days"),
                remediation: .reviewItem,
                estimatedFixSeconds: AuditFixEstimate.reviewItem,
                detectedAt: context.now)
        }
    }
}
