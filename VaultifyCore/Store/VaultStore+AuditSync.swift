import Foundation
import SwiftData

/// Audit report + finding-state persistence and sync reconciliation.
/// Both types follow the folder pattern: single content LWW gate on
/// `updatedAt`, changeTag no-op short-circuit, local-win re-dirty.
extension VaultStore {

    // MARK: - Audit reports (append-only, pruned)

    /// Reports kept per persona; older ones become tombstones (synced deletes).
    static let auditReportRetention = 50

    @MainActor
    func allAuditReportRecords() -> [AuditReportRecord] {
        (try? context.fetch(FetchDescriptor<AuditReportRecord>())) ?? []
    }

    @MainActor
    func auditReportRecord(id: String) -> AuditReportRecord? {
        var descriptor = FetchDescriptor<AuditReportRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Live (non-tombstoned) reports for a persona, newest first.
    @MainActor
    func auditReports(personaID: String?) -> [AuditReportRecord] {
        allAuditReportRecords()
            .filter { $0.deletedAt == nil && $0.personaID == personaID }
            .sorted { $0.completedAt > $1.completedAt }
    }

    /// Insert a completed report and tombstone anything beyond the retention cap.
    @MainActor
    func insertAuditReport(_ record: AuditReportRecord) {
        context.insert(record)
        let live = auditReports(personaID: record.personaID)
        for stale in live.dropFirst(Self.auditReportRetention) {
            stale.deletedAt = .now
            stale.updatedAt = .now   // tombstone must ride the content gate
            stale.dirty = true
        }
        try? context.save()
    }

    @MainActor
    func upsertAuditReportFromRemote(id: String, personaID: String?, sealed: Data,
                                     completedAt: Date, deletedAt: Date?,
                                     createdAt: Date, updatedAt: Date, changeTag: String?) {
        if let existing = auditReportRecord(id: id) {
            if let changeTag, changeTag == existing.ckChangeTag { return }
            guard updatedAt > existing.updatedAt else {
                if existing.updatedAt > updatedAt {
                    existing.dirty = true
                    try? context.save()
                }
                return
            }
            existing.sealed = sealed
            existing.personaID = personaID
            existing.completedAt = completedAt
            existing.deletedAt = deletedAt
            existing.updatedAt = updatedAt
            existing.ckChangeTag = changeTag
            existing.dirty = false
        } else {
            let record = AuditReportRecord(id: id, personaID: personaID, sealed: sealed,
                                           completedAt: completedAt,
                                           createdAt: createdAt, updatedAt: updatedAt)
            record.deletedAt = deletedAt
            record.ckChangeTag = changeTag
            record.dirty = false
            context.insert(record)
        }
        try? context.save()
    }

    @MainActor
    func markAuditReportSynced(_ record: AuditReportRecord, changeTag: String?,
                               snapshotUpdatedAt: Date) {
        record.ckChangeTag = changeTag
        if record.updatedAt == snapshotUpdatedAt { record.dirty = false }
        try? context.save()
    }

    // MARK: - Finding states (fingerprint-keyed user decisions)

    @MainActor
    func allFindingStateRecords() -> [FindingStateRecord] {
        (try? context.fetch(FetchDescriptor<FindingStateRecord>())) ?? []
    }

    @MainActor
    func findingStateRecord(id: String) -> FindingStateRecord? {
        var descriptor = FetchDescriptor<FindingStateRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Live states for a persona keyed by fingerprint.
    @MainActor
    func findingStates(personaID: String?) -> [String: FindingStateRecord] {
        Dictionary(uniqueKeysWithValues: allFindingStateRecords()
            .filter { $0.deletedAt == nil && $0.personaID == personaID }
            .map { ($0.id, $0) })
    }

    /// Write (or overwrite) a user decision. Always bumps `updatedAt` + `dirty`
    /// — a state change that skips the bump would be dropped on the next pull.
    @MainActor
    func setFindingState(fingerprint: String, personaID: String?, sealed: Data, status: String) {
        if let existing = findingStateRecord(id: fingerprint) {
            existing.sealed = sealed
            existing.status = status
            existing.personaID = personaID
            existing.deletedAt = nil
            existing.updatedAt = .now
            existing.dirty = true
        } else {
            context.insert(FindingStateRecord(id: fingerprint, personaID: personaID,
                                              sealed: sealed, status: status))
        }
        try? context.save()
    }

    /// Remove a user decision (revert to open) via tombstone so it syncs.
    @MainActor
    func clearFindingState(fingerprint: String) {
        guard let existing = findingStateRecord(id: fingerprint) else { return }
        existing.deletedAt = .now
        existing.updatedAt = .now
        existing.dirty = true
        try? context.save()
    }

    @MainActor
    func upsertFindingStateFromRemote(id: String, personaID: String?, sealed: Data,
                                      status: String, deletedAt: Date?,
                                      createdAt: Date, updatedAt: Date, changeTag: String?) {
        if let existing = findingStateRecord(id: id) {
            if let changeTag, changeTag == existing.ckChangeTag { return }
            guard updatedAt > existing.updatedAt else {
                if existing.updatedAt > updatedAt {
                    existing.dirty = true
                    try? context.save()
                }
                return
            }
            existing.sealed = sealed
            existing.status = status
            existing.personaID = personaID
            existing.deletedAt = deletedAt
            existing.updatedAt = updatedAt
            existing.ckChangeTag = changeTag
            existing.dirty = false
        } else {
            let record = FindingStateRecord(id: id, personaID: personaID,
                                            sealed: sealed, status: status,
                                            createdAt: createdAt, updatedAt: updatedAt)
            record.deletedAt = deletedAt
            record.ckChangeTag = changeTag
            record.dirty = false
            context.insert(record)
        }
        try? context.save()
    }

    @MainActor
    func markFindingStateSynced(_ record: FindingStateRecord, changeTag: String?,
                                snapshotUpdatedAt: Date) {
        record.ckChangeTag = changeTag
        if record.updatedAt == snapshotUpdatedAt { record.dirty = false }
        try? context.save()
    }
}
