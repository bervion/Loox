import Foundation

/// Known-leak check against the HIBP Pwned Passwords range API (k-anonymity).
/// Network rule: runs only when online checks are enabled, fails soft in the
/// coordinator. Lives in the app target — the AutoFill extension never audits.
/// Lookup mechanics (dedupe, prefix grouping, bounded concurrency, device-local
/// cache) live in `PwnedPasswordChecker`.
nonisolated struct PwnedPasswordRule: nonisolated AuditRule {
    let id = "exposure.leaked"
    let version = 1
    let category = AuditCategory.exposure
    let requiresNetwork = true

    var checker = PwnedPasswordChecker(cache: try? AuditLocalCache())

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        let items = snapshot.activeItems.filter(\.hasPassword)
        guard !items.isEmpty else { return [] }

        // Reuse map: leaked + reused escalates to critical (blast radius).
        var passwordUse: [String: Int] = [:]
        for item in items { passwordUse[item.password!, default: 0] += 1 }

        let counts = try await checker.counts(for: passwordUse.keys)

        return items.compactMap { item in
            guard let password = item.password, let seen = counts[password], seen > 0 else {
                return nil
            }
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                severity: passwordUse[password, default: 1] > 1 ? .critical : .high,
                category: category,
                affectedItemIDs: [item.id],
                fingerprint: AuditFingerprint.make(
                    ruleID: id, version: version, itemIDs: [item.id],
                    marker: AuditFingerprint.secretMarker(password, key: context.secretMarkerKey)),
                titleKey: "finding.exposure.leaked.title",
                detail: appString("Seen \(seen) times in breaches"),
                remediation: .changePassword,
                estimatedFixSeconds: AuditFixEstimate.changeLeakedPassword,
                detectedAt: context.now)
        }
    }
}
