import Foundation

/// Flags items whose password grades very weak or weak under the pattern-aware
/// engine. One finding per item — remediation (change the password) is
/// per-item. "Fair" is deliberately NOT an issue (over-warning fatigue); it
/// only shows in the strength breakdown screen.
///
/// A second finding fires when the password echoes vault-known context
/// (username, email, site, title) — that is guessable by anyone targeting
/// this specific account even when the password is otherwise long.
nonisolated struct PasswordStrengthRule: nonisolated AuditRule {
    let id = "quality.weak"
    let version = 1
    let category = AuditCategory.quality

    static let contextRuleID = "quality.contains-context"

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        var findings: [AuditFinding] = []
        for item in snapshot.activeItems {
            guard let password = item.password, !password.isEmpty else { continue }
            let result = PasswordStrengthEngine.evaluate(password, context: strengthContext(for: item))
            let contextMatched = result.matchedPatterns.contains("context")

            // A context echo produces its own finding below — do not ALSO flag
            // the same password weak (the context cap would double-bill it).
            if result.grade <= .weak, !contextMatched {
                findings.append(AuditFinding(
                    ruleID: id,
                    ruleVersion: version,
                    severity: result.grade == .veryWeak ? .critical : .high,
                    category: category,
                    affectedItemIDs: [item.id],
                    fingerprint: AuditFingerprint.make(ruleID: id, version: version, itemIDs: [item.id]),
                    titleKey: "finding.quality.weak.title",
                    detail: nil,
                    remediation: .changePassword,
                    estimatedFixSeconds: AuditFixEstimate.replaceReusedPassword,
                    detectedAt: context.now))
            }

            if contextMatched {
                findings.append(AuditFinding(
                    ruleID: Self.contextRuleID,
                    ruleVersion: version,
                    severity: .high,
                    category: category,
                    affectedItemIDs: [item.id],
                    fingerprint: AuditFingerprint.make(ruleID: Self.contextRuleID,
                                                       version: version, itemIDs: [item.id]),
                    titleKey: "finding.quality.contains-context.title",
                    detail: nil,
                    remediation: .changePassword,
                    estimatedFixSeconds: AuditFixEstimate.replaceReusedPassword,
                    detectedAt: context.now))
            }
        }
        return findings
    }

    private func strengthContext(for item: VaultAuditItem) -> StrengthContext {
        StrengthContext(
            usernames: item.usernames,
            emailLocalParts: item.usernames.compactMap { name in
                guard let at = name.firstIndex(of: "@"), at != name.startIndex else { return nil }
                return String(name[..<at])
            },
            domains: item.rawURLs.compactMap { DomainNormalizer.normalizedHost(from: $0) },
            itemTitle: item.title.isEmpty ? nil : item.title)
    }
}
