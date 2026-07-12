import CloudKit
import Foundation

/// Shared CloudKit sync primitives used by BOTH the private-DB vault path and
/// the approval control-plane path (extracted so the two never fork — H7):
/// - `ChangeTokenCursor` — a persisted `CKServerChangeToken` keyed cursor.
/// - `ZoneDeltaFetch` — the zone-changes delta loop with `changeTokenExpired`
///   reset-and-refetch recovery.
/// - `SingleFlight` — coalesces concurrent sync requests into one run plus at
///   most one follow-up.

/// Persisted delta cursor. Same archive format the vault path always used, so
/// adopting the helper changes no on-disk state.
@MainActor final class ChangeTokenCursor {
    private let key: String

    init(key: String) { self.key = key }

    var token: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
        }
        set {
            let defaults = UserDefaults.standard
            guard let newValue,
                  let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue,
                                                               requiringSecureCoding: true) else {
                defaults.removeObject(forKey: key)
                return
            }
            defaults.set(data, forKey: key)
        }
    }

    func clear() { token = nil }
}

@MainActor enum ZoneDeltaFetch {
    /// Page through zone changes, invoking `apply` per modified record.
    ///
    /// Two modes — picking the right one matters:
    /// - `cursor` non-nil: DELTA sync ("what changed since last time"),
    ///   advancing token persisted per page. For mirror-style consumers only.
    /// - `cursor` nil: STATELESS full refetch ("what is the current state").
    ///   REQUIRED for state queries (pending requests, shared blobs, response
    ///   lookup) — a persisted cursor there silently hides every record an
    ///   earlier scan already consumed.
    ///
    /// A stale token (`changeTokenExpired` — e.g. the zone was erased and
    /// recreated) resets ONCE to a full refetch. Deletions are intentionally
    /// not surfaced: the vault path travels tombstones, and approval zones
    /// signal revocation by whole-zone deletion (`zoneNotFound`).
    static func pull(database: CKDatabase, zoneID: CKRecordZone.ID,
                     cursor: ChangeTokenCursor?,
                     apply: (CKRecord) -> Void) async throws {
        var token = cursor?.token
        var didResetToken = false
        while true {
            let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                          deletions: [CKDatabase.RecordZoneChange.Deletion],
                          changeToken: CKServerChangeToken,
                          moreComing: Bool)
            do {
                changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
            } catch let error as CKError where error.code == .changeTokenExpired && !didResetToken {
                token = nil
                cursor?.clear()
                didResetToken = true
                continue
            }
            for (_, result) in changes.modificationResultsByID {
                guard case .success(let modification) = result else { continue }
                apply(modification.record)
            }
            token = changes.changeToken
            cursor?.token = changes.changeToken
            guard changes.moreComing else { break }
        }
    }

    /// Database-level delta (which zones changed) — the shared-DB entry point.
    /// Same reset-once recovery for an expired DATABASE token.
    static func changedZoneIDs(database: CKDatabase,
                               cursor: ChangeTokenCursor) async throws -> [CKRecordZone.ID] {
        var token = cursor.token
        var didResetToken = false
        var zoneIDs: [CKRecordZone.ID] = []
        while true {
            let changes: (modifications: [CKDatabase.DatabaseChange.Modification],
                          deletions: [CKDatabase.DatabaseChange.Deletion],
                          changeToken: CKServerChangeToken,
                          moreComing: Bool)
            do {
                changes = try await database.databaseChanges(since: token)
            } catch let error as CKError where error.code == .changeTokenExpired && !didResetToken {
                token = nil
                cursor.clear()
                didResetToken = true
                continue
            }
            zoneIDs.append(contentsOf: changes.modifications.map(\.zoneID))
            token = changes.changeToken
            cursor.token = changes.changeToken
            guard changes.moreComing else { break }
        }
        return zoneIDs
    }
}

/// While a run is in progress, further requests coalesce into ONE follow-up
/// run (the pattern previously inlined in `SyncCoordinator`).
///
/// Coalesced callers SUSPEND until the in-flight run plus that follow-up
/// completes, so `await run { … }` always means "a full pass finished after
/// this call". The background push path relies on that: the push delegate
/// holds the system fetch completion handler for the real duration of the
/// triggered CloudKit work, no matter which trigger won the race to start it.
@MainActor final class SingleFlight {
    private var inFlight = false
    private var followUpRequested = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run(_ operation: () async -> Void) async {
        if inFlight {
            followUpRequested = true
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        inFlight = true
        repeat {
            followUpRequested = false
            await operation()
        } while followUpRequested
        inFlight = false
        while !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}
