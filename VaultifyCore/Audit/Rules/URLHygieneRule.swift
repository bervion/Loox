import Foundation

/// Website-field sanity checks. Deliberately shallow (proposal §11): format
/// problems only — no reachability, no TLS grading, no phishing verdicts.
/// Emits distinct ruleIDs per problem so each has its own copy and severity.
nonisolated struct URLHygieneRule: nonisolated AuditRule {
    let id = "url.hygiene"
    let version = 1
    let category = AuditCategory.integrity

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        var findings: [AuditFinding] = []
        for item in snapshot.activeItems {
            // One finding per problem KIND per item (not per URL) keeps noise down.
            var flagged: Set<String> = []
            for raw in item.rawURLs {
                let value = raw.trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { continue }
                if let problem = classify(value) { flagged.insert(problem) }
            }
            for problem in flagged.sorted() {
                findings.append(finding(problem: problem, item: item, now: context.now))
            }
        }
        return findings
    }

    /// Returns the problem ruleID suffix, or nil when the URL looks fine.
    private func classify(_ value: String) -> String? {
        guard let host = DomainNormalizer.host(from: value), !host.contains(" ") else {
            return "malformed"
        }
        if value.lowercased().hasPrefix("http://") { return "insecure-http" }
        if host.split(separator: ".").contains(where: { $0.hasPrefix("xn--") }) { return "punycode" }
        if isIPLiteral(host) { return "ip-login" }
        return nil
    }

    private func isIPLiteral(_ host: String) -> Bool {
        if host.hasPrefix("[") { return true }   // bracketed IPv6
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }

    private func finding(problem: String, item: VaultAuditItem, now: Date) -> AuditFinding {
        let ruleID = "url.\(problem)"
        let severity: AuditSeverity = switch problem {
        case "insecure-http", "punycode": .medium
        default: .low
        }
        return AuditFinding(
            ruleID: ruleID,
            ruleVersion: version,
            severity: severity,
            category: category,
            affectedItemIDs: [item.id],
            fingerprint: AuditFingerprint.make(ruleID: ruleID, version: version, itemIDs: [item.id]),
            titleKey: "finding.\(ruleID).title",
            detail: nil,
            remediation: .fixData,
            estimatedFixSeconds: AuditFixEstimate.reviewItem,
            detectedAt: now)
    }
}
