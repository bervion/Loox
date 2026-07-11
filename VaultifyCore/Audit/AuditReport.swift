import Foundation

/// The six score pillars, in display order. Raw values are stable identifiers
/// persisted in report payloads — never rename.
nonisolated enum AuditPillar: String, Codable, Sendable, CaseIterable {
    case exposure, quality, reuseIsolation, authReadiness, integrity, maintenance

    var maxPoints: Int {
        switch self {
        case .exposure: return ScoringWeights.exposureMax
        case .quality: return ScoringWeights.qualityMax
        case .reuseIsolation: return ScoringWeights.reuseMax
        case .authReadiness: return ScoringWeights.authMax
        case .integrity: return ScoringWeights.integrityMax
        case .maintenance: return ScoringWeights.maintenanceMax
        }
    }
}

nonisolated struct PillarScore: Codable, Sendable, Equatable {
    let pillar: AuditPillar
    let earned: Int
    var max: Int { pillar.maxPoints }
}

/// Complete outcome of one audit run: findings plus the explainable score.
nonisolated struct AuditReport: Sendable {
    /// 0…1000, always the exact sum of the pillar scores.
    let score: Int
    let pillars: [PillarScore]
    let findings: [AuditFinding]
    let analyzedItemCount: Int
    let uniquePasswordCount: Int
    let domainCount: Int
    /// True when the vault is too small for the score to carry much weight —
    /// UI shows "Based on N items" (score is never artificially scaled).
    let confidenceLimited: Bool
    let startedAt: Date
    let completedAt: Date
    let onlineChecksCompleted: Bool
    let ruleVersions: [String: Int]

    var earned: [AuditPillar: Int] {
        Dictionary(uniqueKeysWithValues: pillars.map { ($0.pillar, $0.earned) })
    }
}
