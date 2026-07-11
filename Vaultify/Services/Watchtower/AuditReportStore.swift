import Foundation

/// High-level persistence for audit runs: seals report payloads under the
/// Vault Key, reads history, and owns the finding-status lifecycle. Storage
/// and sync mechanics live in `VaultStore+AuditSync`; this layer is the only
/// place that touches the key.
@MainActor final class AuditReportStore {
    private let store: VaultStore

    init(store: VaultStore) {
        self.store = store
    }

    // MARK: - Reports

    func save(report: AuditReport, personaID: String?, key: SecureBytes) throws {
        let sealed = try AuditReportPayload(report).sealed(key: key)
        store.insertAuditReport(AuditReportRecord(personaID: personaID, sealed: sealed,
                                                  completedAt: report.completedAt))
    }

    /// Newest-first payload history (undecryptable records are skipped, never fatal).
    func history(personaID: String?, key: SecureBytes) -> [AuditReportPayload] {
        store.auditReports(personaID: personaID).compactMap {
            try? AuditReportPayload.open($0.sealed, key: key)
        }
    }

    func latest(personaID: String?, key: SecureBytes) -> AuditReportPayload? {
        guard let record = store.auditReports(personaID: personaID).first else { return nil }
        return try? AuditReportPayload.open(record.sealed, key: key)
    }

    /// From the plaintext `completedAt` column — usable before unlock. Nil on
    /// the first ever audit (no maintenance penalty).
    func daysSinceLastCompletedAudit(personaID: String?, now: Date = .now) -> Int? {
        guard let last = store.auditReports(personaID: personaID).first?.completedAt else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: last, to: now).day
    }

    // MARK: - Finding states (user decisions)

    func setState(_ status: FindingStatus, reason: String? = nil, snoozedUntil: Date? = nil,
                  for finding: AuditFinding, personaID: String?, key: SecureBytes) throws {
        let payload = FindingStatePayload(status: status, reason: reason,
                                          snoozedUntil: snoozedUntil,
                                          ruleID: finding.ruleID,
                                          ruleVersion: finding.ruleVersion)
        store.setFindingState(fingerprint: finding.fingerprint, personaID: personaID,
                              sealed: try payload.sealed(key: key), status: status.rawValue)
    }

    func clearState(fingerprint: String) {
        store.clearFindingState(fingerprint: fingerprint)
    }

    /// Effective status of a finding produced by the CURRENT audit run.
    ///
    /// Derivation, not storage: a stored user decision applies only while the
    /// rule version it was made under still matches (a bumped rule resurfaces
    /// the finding as `needsRecheck`), and an expired snooze reopens it.
    func effectiveStatus(of finding: AuditFinding, personaID: String?,
                         key: SecureBytes, now: Date = .now) -> FindingStatus {
        guard let record = store.findingStates(personaID: personaID)[finding.fingerprint],
              let payload = try? FindingStatePayload.open(record.sealed, key: key) else {
            return .open
        }
        if payload.ruleVersion < finding.ruleVersion { return .needsRecheck }
        if let snoozedUntil = payload.snoozedUntil, snoozedUntil <= now { return .open }
        return payload.status
    }

    /// Cross-run derivation for history/diff screens: fingerprints present in
    /// `previous` but absent from `current` are resolved — unless every affected
    /// item vanished from the vault, which is "no longer monitored", not "fixed".
    nonisolated static func disappearedStatus(previous: FindingDigest,
                                              currentItemIDs: Set<String>) -> FindingStatus {
        previous.affectedItemIDs.allSatisfy { !currentItemIDs.contains($0) }
            ? .noLongerMonitored : .resolved
    }
}
