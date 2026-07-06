import CloudKit
import Foundation

/// Extension-side authoritative fill gate (INV-11): confirms the grant a
/// cached shared credential came from is STILL live in the owner's shared
/// zone, immediately before the credential is handed to the OS. Fail-closed:
/// any error or deadline hit blocks the fill — a satisfied network path alone
/// never authorizes (INV-02).
///
/// Lives in VaultifyCore because the AutoFill extension links only the core;
/// the full record mapping stays app-side, so the one field this check needs
/// is mirrored here (kept in sync with `ApprovalRecordMapping.Field.blob`).
nonisolated enum SharedGrantLiveCheck {
    enum Outcome: Sendable {
        case authorized
        /// Zone/grant gone, or the grant id rotated away from the cached one —
        /// this credential's authorization no longer exists.
        case revoked
        /// Transient failure or deadline hit — fail closed, distinct from
        /// offline and from revoked (INV-03).
        case unavailable
    }

    /// Mirrors `ApprovalRecordMapping.Field.blob` (app target).
    private static let blobField = "blob"

    static func verify(zoneName: String, ownerName: String,
                       expectedGrantId: String,
                       policy: SharedAccessTimingPolicy = .standard) async -> Outcome {
        // A build without the provisioned container can't verify anything —
        // fail closed rather than pretending (same flag CloudSyncService uses).
        #if !VAULTIFY_ICLOUD
        return .unavailable
        #else
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        let recordID = CKRecord.ID(recordName: ApprovalConfig.grantRecordName, zoneID: zoneID)
        do {
            let record = try await withDeadline(policy.grantVerificationDeadline) {
                try await CKContainer(identifier: ApprovalConfig.containerID)
                    .sharedCloudDatabase.record(for: recordID)
            }
            guard let blob = record[blobField] as? Data,
                  let grant = try? AccessGrant.decode(blob) else {
                return .unavailable
            }
            return grant.id == expectedGrantId ? .authorized : .revoked
        } catch let error as CKError
            where error.code == .zoneNotFound || error.code == .userDeletedZone
                || error.code == .unknownItem {
            return .revoked
        } catch {
            return .unavailable
        }
        #endif
    }

    private static func withDeadline<T: Sendable>(
        _ deadline: Duration,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw CancellationError()
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }
}
