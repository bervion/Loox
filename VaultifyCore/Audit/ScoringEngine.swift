import Foundation

/// Turns an audit run into the 1000-point Vault Health score. Deterministic:
/// same snapshot + findings always produce the same report. Group-based
/// penalties throughout — a 20-item import never zeroes a pillar on its own.
nonisolated enum ScoringEngine {

    /// - Parameter daysSinceLastCompletedAudit: nil on the first ever audit.
    static func report(snapshot: VaultAuditSnapshot,
                       run: AuditRunResult,
                       daysSinceLastCompletedAudit: Int? = nil) -> AuditReport {
        let items = snapshot.activeItems
        let withPassword = items.filter(\.hasPassword)
        let leakedItemIDs = Set(run.findings.filter { $0.ruleID == "exposure.leaked" }
            .flatMap(\.affectedItemIDs))

        let pillars = [
            PillarScore(pillar: .exposure,
                        earned: exposure(withPassword: withPassword, leakedItemIDs: leakedItemIDs)),
            PillarScore(pillar: .quality,
                        earned: quality(withPassword: withPassword, leakedItemIDs: leakedItemIDs)),
            PillarScore(pillar: .reuseIsolation,
                        earned: reuseIsolation(findings: run.findings, snapshot: snapshot)),
            PillarScore(pillar: .authReadiness,
                        earned: authReadiness(items: items, findings: run.findings)),
            PillarScore(pillar: .integrity, earned: integrity(findings: run.findings)),
            PillarScore(pillar: .maintenance,
                        earned: maintenance(findings: run.findings,
                                            daysSinceLastCompletedAudit: daysSinceLastCompletedAudit)),
        ]

        let domains = Set(items.flatMap(\.rawURLs).compactMap { DomainNormalizer.normalizedHost(from: $0) })
        return AuditReport(
            score: pillars.reduce(0) { $0 + $1.earned },
            pillars: pillars,
            findings: run.findings,
            analyzedItemCount: withPassword.count,
            uniquePasswordCount: Set(withPassword.compactMap(\.password)).count,
            domainCount: domains.count,
            confidenceLimited: withPassword.count < ScoringWeights.lowConfidenceItemCount
                && withPassword.count > 0,
            startedAt: run.startedAt,
            completedAt: run.completedAt,
            onlineChecksCompleted: run.onlineChecksCompleted,
            ruleVersions: run.ruleVersions)
    }

    // MARK: - Exposure (300): unique leaked passwords, reuse multiplies

    private static func exposure(withPassword: [VaultAuditItem], leakedItemIDs: Set<String>) -> Int {
        var useCount: [String: Int] = [:]
        for item in withPassword { useCount[item.password!, default: 0] += 1 }

        let leakedPasswords = Set(withPassword.filter { leakedItemIDs.contains($0.id) }
            .compactMap(\.password))
        var penalty = 0
        for password in leakedPasswords {
            penalty += ScoringWeights.leakedPasswordPenalty
            switch useCount[password, default: 1] {
            case 4...: penalty += ScoringWeights.leakedReusedLargeExtra
            case 2...3: penalty += ScoringWeights.leakedReusedSmallExtra
            default: break
            }
        }
        return max(0, ScoringWeights.exposureMax - penalty)
    }

    // MARK: - Quality (220): weighted grade distribution

    private static func quality(withPassword: [VaultAuditItem], leakedItemIDs: Set<String>) -> Int {
        // Leaked items are already billed in Exposure — exclude them here so a
        // single bad password is not double-penalized into the ground.
        let scored = withPassword.filter { !leakedItemIDs.contains($0.id) }
        guard !scored.isEmpty else { return ScoringWeights.qualityMax }

        var gradeCache: [String: PasswordGrade] = [:]
        var total = 0.0
        for item in scored {
            let password = item.password!
            let grade = gradeCache[password]
                ?? PasswordStrengthEngine.evaluate(password).grade
            gradeCache[password] = grade
            total += ScoringWeights.gradeValue[grade, default: 0]
        }
        return Int((total / Double(scored.count) * Double(ScoringWeights.qualityMax)).rounded())
    }

    // MARK: - Reuse isolation (180): per-group, category-weighted, capped

    private static func reuseIsolation(findings: [AuditFinding], snapshot: VaultAuditSnapshot) -> Int {
        let itemsByID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })
        var penalty = 0.0
        for group in findings where group.ruleID == "reuse.exact" {
            // The group's blast radius is its most sensitive member.
            let weight = group.affectedItemIDs
                .compactMap { itemsByID[$0] }
                .flatMap(\.rawURLs)
                .compactMap { DomainNormalizer.normalizedHost(from: $0) }
                .map { ScoringWeights.categoryWeight(forHost: $0) }
                .max() ?? 1.0
            let raw = ScoringWeights.reusePerExtraItem * Double(group.affectedItemIDs.count - 1) * weight
            penalty += min(raw, ScoringWeights.reuseGroupCap)
        }
        return max(0, ScoringWeights.reuseMax - Int(penalty.rounded()))
    }

    // MARK: - Auth readiness (140): confirmed protection >> opportunities

    private static func authReadiness(items: [VaultAuditItem], findings: [AuditFinding]) -> Int {
        let confirmedIDs = Set(items.filter { $0.category == .login && ($0.hasTOTP || $0.hasPasskey) }
            .map(\.id))
        // Unique ITEMS with no confirmed protection at all: a login that already
        // holds a TOTP but could add a passkey is covered, not an opportunity;
        // and one missing both TOTP and passkey is one opportunity, not two.
        let opportunities = Set(findings.filter { $0.category == .authentication }
            .flatMap(\.affectedItemIDs)).subtracting(confirmedIDs).count
        let confirmed = confirmedIDs.count
        let eligible = confirmed + opportunities
        guard eligible > 0 else { return ScoringWeights.authMax }
        let coverage = Double(confirmed) / Double(eligible)
        let floor = ScoringWeights.authCoverageFloor
        return Int((Double(ScoringWeights.authMax) * (floor + (1 - floor) * coverage)).rounded())
    }

    // MARK: - Integrity (100)

    private static func integrity(findings: [AuditFinding]) -> Int {
        var penalty = 0
        for finding in findings {
            switch finding.ruleID {
            case "integrity.duplicate-conflict": penalty += ScoringWeights.conflictPenalty
            case "integrity.duplicate-exact": penalty += ScoringWeights.exactDuplicatePenalty
            case "integrity.otp-invalid": penalty += ScoringWeights.invalidOTPPenalty
            case "integrity.incomplete": penalty += ScoringWeights.incompleteItemPenalty
            case let id where id.hasPrefix("url."):
                penalty += finding.severity >= .medium
                    ? ScoringWeights.urlMediumPenalty : ScoringWeights.urlLowPenalty
            default: break
            }
        }
        return max(0, ScoringWeights.integrityMax - penalty)
    }

    // MARK: - Maintenance (60)

    private static func maintenance(findings: [AuditFinding],
                                    daysSinceLastCompletedAudit: Int?) -> Int {
        let stale = findings.filter { $0.ruleID == "maintenance.stale" }.count
        let metadata = findings.filter { $0.ruleID == "maintenance.missing-metadata" }.count
        var penalty = min(stale * ScoringWeights.stalePenalty, ScoringWeights.staleCap)
        penalty += min(metadata * ScoringWeights.missingMetadataPenalty,
                       ScoringWeights.missingMetadataCap)
        if let days = daysSinceLastCompletedAudit {
            if days > 90 { penalty += ScoringWeights.auditOverdue90Penalty }
            else if days > 30 { penalty += ScoringWeights.auditOverdue30Penalty }
        }
        return max(0, ScoringWeights.maintenanceMax - penalty)
    }
}
