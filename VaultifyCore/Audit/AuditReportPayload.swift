import Foundation

/// Compact digest of one finding for persistence/history — identity and
/// classification only. NEVER carries titles, details, passwords, hashes, or
/// HIBP data; the full finding is recomputed by re-running the audit.
nonisolated struct FindingDigest: Codable, Sendable, Equatable {
    let fingerprint: String
    let ruleID: String
    let severity: AuditSeverity
    /// Item UUIDs (sealed with the payload) — needed to tell "resolved" from
    /// "no longer monitored" when a finding disappears between runs.
    let affectedItemIDs: [String]

    init(_ finding: AuditFinding) {
        fingerprint = finding.fingerprint
        ruleID = finding.ruleID
        severity = finding.severity
        affectedItemIDs = finding.affectedItemIDs
    }
}

/// The sealed content of an `AuditReportRecord`.
nonisolated struct AuditReportPayload: Codable, Sendable {
    let score: Int
    let pillars: [PillarScore]
    let findings: [FindingDigest]
    let analyzedItemCount: Int
    let uniquePasswordCount: Int
    let domainCount: Int
    let confidenceLimited: Bool
    let onlineChecksCompleted: Bool
    let startedAt: Date
    let completedAt: Date
    let ruleVersions: [String: Int]

    init(_ report: AuditReport) {
        score = report.score
        pillars = report.pillars
        findings = report.findings.map(FindingDigest.init)
        analyzedItemCount = report.analyzedItemCount
        uniquePasswordCount = report.uniquePasswordCount
        domainCount = report.domainCount
        confidenceLimited = report.confidenceLimited
        onlineChecksCompleted = report.onlineChecksCompleted
        startedAt = report.startedAt
        completedAt = report.completedAt
        ruleVersions = report.ruleVersions
    }

    func sealed(key: SecureBytes) throws -> Data {
        try AESGCM.seal(JSONEncoder().encode(self), key: key)
    }

    static func open(_ sealed: Data, key: SecureBytes) throws -> AuditReportPayload {
        try JSONDecoder().decode(AuditReportPayload.self, from: AESGCM.open(sealed, key: key))
    }
}

/// The sealed content of a `FindingStateRecord`.
nonisolated struct FindingStatePayload: Codable, Sendable {
    let status: FindingStatus
    /// User-chosen dismissal reason key (phase 08 dismiss sheet), if any.
    let reason: String?
    /// "Remind me later" horizon; nil for permanent states.
    let snoozedUntil: Date?
    /// Rule identity at decision time — a later rule version bump surfaces the
    /// finding again as "needs review" instead of staying silently ignored.
    let ruleID: String
    let ruleVersion: Int

    func sealed(key: SecureBytes) throws -> Data {
        try AESGCM.seal(JSONEncoder().encode(self), key: key)
    }

    static func open(_ sealed: Data, key: SecureBytes) throws -> FindingStatePayload {
        try JSONDecoder().decode(FindingStatePayload.self, from: AESGCM.open(sealed, key: key))
    }
}
