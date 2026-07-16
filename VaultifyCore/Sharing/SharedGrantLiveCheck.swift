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
        let database = CKContainer(identifier: ApprovalConfig.containerID).sharedCloudDatabase
        let perGrantID = CKRecord.ID(recordName: ApprovalConfig.grantRecordName(grantId: expectedGrantId),
                                     zoneID: zoneID)
        let legacyID = CKRecord.ID(recordName: ApprovalConfig.legacyGrantRecordName, zoneID: zoneID)

        let probes: (perGrant: ProbeResult, legacy: ProbeResult)
        do {
            probes = try await withDeadline(policy.grantVerificationDeadline) {
                // Concurrent, not sequential: a per-grant miss (expected
                // whenever FamilyShareTransport.perGrantEnabled is off) must
                // not cost a full extra round trip before the legacy lookup
                // even starts — both names race under the SAME deadline.
                async let perGrant = Self.probe(recordID: perGrantID, database: database)
                async let legacy = Self.probe(recordID: legacyID, database: database)
                return await (perGrant, legacy)
            }
        } catch {
            return .unavailable // deadline hit
        }

        // Prefer the per-grant record when both resolved — which one
        // "wins" is only a preference; the authorization check below is
        // always against the decoded blob's own id (INV-FAM-01).
        if case .found(let grant) = probes.perGrant {
            return grant.id == expectedGrantId ? .authorized : .revoked
        }
        if case .found(let grant) = probes.legacy {
            return grant.id == expectedGrantId ? .authorized : .revoked
        }
        // Neither name resolved a usable grant. INV-03: `.revoked` only
        // when BOTH probes are a DEFINITIVE absence — an expected per-grant
        // miss (flag off) must never mask a real legacy revocation, and a
        // transient failure on EITHER side must never read as revoked.
        if case .definitelyAbsent = probes.perGrant, case .definitelyAbsent = probes.legacy {
            return .revoked
        }
        return .unavailable
        #endif
    }

    #if VAULTIFY_ICLOUD
    /// Outcome of fetching one candidate grant record. `.inconclusive`
    /// covers both "some OTHER error" (network, throttling) AND "the record
    /// exists but its payload didn't decode" — a malformed record is not
    /// the same signal as "nothing there" (INV-03), so it must never
    /// contribute to a `.revoked` verdict.
    private enum ProbeResult: Sendable {
        case found(AccessGrant)
        case definitelyAbsent
        case inconclusive
    }

    /// Probe ONE candidate record name. Matched by the decoded blob's own
    /// `id` at the call site above — never inferred from which name the
    /// record was found under (INV-FAM-01).
    private static func probe(recordID: CKRecord.ID, database: CKDatabase) async -> ProbeResult {
        do {
            let record = try await database.record(for: recordID)
            guard let blob = record[blobField] as? Data, let grant = try? AccessGrant.decode(blob) else {
                return .inconclusive
            }
            return .found(grant)
        } catch let error as CKError
            where error.code == .zoneNotFound || error.code == .userDeletedZone
                || error.code == .unknownItem {
            return .definitelyAbsent
        } catch {
            return .inconclusive
        }
    }
    #endif

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
