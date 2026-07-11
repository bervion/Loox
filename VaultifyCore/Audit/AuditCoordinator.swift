import Foundation

/// Progress signal for the Running screen: which rule just finished.
nonisolated struct AuditProgress: Sendable {
    let ruleID: String
    let completedRules: Int
    let totalRules: Int
}

/// Output of one audit run (pre-scoring). `onlineChecksCompleted` is false when
/// network rules were skipped (offline / disabled) or any of them failed —
/// local results remain valid either way.
nonisolated struct AuditRunResult: Sendable {
    let findings: [AuditFinding]
    let startedAt: Date
    let completedAt: Date
    let onlineChecksCompleted: Bool
    let ruleVersions: [String: Int]
}

/// Runs the rule registry over a snapshot. Local rules run first (an offline
/// audit is always complete for them); network rules run after and fail soft.
/// Cooperative cancellation: a cancelled audit throws and must NOT be recorded.
nonisolated struct AuditCoordinator: Sendable {
    private let localRules: [any AuditRule]
    private let networkRules: [any AuditRule]

    init(rules: [any AuditRule]) {
        localRules = rules.filter { !$0.requiresNetwork }
        networkRules = rules.filter(\.requiresNetwork)
    }

    func run(snapshot: VaultAuditSnapshot,
             context: AuditContext,
             progress: (@Sendable (AuditProgress) -> Void)? = nil) async throws -> AuditRunResult {
        let startedAt = context.now
        var findings: [AuditFinding] = []
        var ruleVersions: [String: Int] = [:]

        let activeNetworkRules = context.onlineChecksEnabled ? networkRules : []
        let totalRules = localRules.count + activeNetworkRules.count
        var completed = 0

        for rule in localRules {
            try Task.checkCancellation()
            findings += try await rule.evaluate(snapshot, context: context)
            ruleVersions[rule.id] = rule.version
            completed += 1
            progress?(AuditProgress(ruleID: rule.id, completedRules: completed, totalRules: totalRules))
        }

        // Network rules fail soft: one unreachable service must not void the
        // local audit. Cancellation still propagates (it is not a rule failure).
        var onlineChecksCompleted = context.onlineChecksEnabled && !networkRules.isEmpty
        if !context.onlineChecksEnabled { onlineChecksCompleted = false }
        for rule in activeNetworkRules {
            try Task.checkCancellation()
            do {
                findings += try await rule.evaluate(snapshot, context: context)
                ruleVersions[rule.id] = rule.version
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                onlineChecksCompleted = false
            }
            completed += 1
            progress?(AuditProgress(ruleID: rule.id, completedRules: completed, totalRules: totalRules))
        }

        return AuditRunResult(findings: findings,
                              startedAt: startedAt,
                              completedAt: .now,
                              onlineChecksCompleted: onlineChecksCompleted,
                              ruleVersions: ruleVersions)
    }
}
