import CloudKit
import Foundation

/// Layer B of the shared-vault access gate: drives the per-item state machine
/// that decides whether shared VALUES may enter the render tree (INV-01/02/03).
///
/// The UI must `guard case .authorized` before building any value-bearing
/// view — there is deliberately no path from a satisfied network path
/// (Layer A) straight to rendering, and no "render cached, verify later".
@MainActor @Observable final class SharedAccessAuthorizer {
    nonisolated enum State: Equatable {
        /// Network path not satisfied — "Cần kết nối mạng".
        case offline
        /// Authoritative check in flight — values are NOT materialized.
        case verifying
        /// The live grant matched the projected grant (id + epoch) just now.
        case authorized
        /// Verification failed or timed out — fail closed. NOT the same as
        /// offline (INV-03): the network was there, the proof wasn't.
        case unavailable
        /// Grant/zone is gone — the item is being purged from the projection.
        case revoked
    }

    private(set) var state: State = .verifying
    @ObservationIgnored private let policy = SharedAccessTimingPolicy.standard
    /// Monotonic run token: a slower, earlier verification must never
    /// overwrite the state a later run produced (stale-result guard, INV-06).
    @ObservationIgnored private var runToken = 0

    /// Pure outcome mapping (unit-tested): live-fetch result → state.
    /// Alive means the SAME grant at the SAME epoch the projection holds —
    /// an id/epoch drift means our projection is stale, so fail closed and
    /// let a projection refresh reconcile.
    nonisolated static func outcome(expectedGrantId: String, expectedEpoch: UInt32,
                                    live: Result<(id: String, epoch: UInt32), any Error>) -> State {
        switch live {
        case .success(let grant):
            return grant.id == expectedGrantId && grant.epoch == expectedEpoch
                ? .authorized : .unavailable
        case .failure(let error as CKError)
            where error.code == .zoneNotFound || error.code == .userDeletedZone:
            return .revoked
        case .failure:
            return .unavailable
        }
    }

    /// One full gate pass. Re-run on: appear, reachability change, scene
    /// becoming active (covers the background-revoke race: values were torn
    /// down with the view, and the first tap after foreground finds
    /// `.verifying`, not `.authorized`).
    func refresh(itemID: String, env: AppEnvironment) async {
        runToken += 1
        let token = runToken

        guard env.reachability.hasSatisfiedNetworkPath else {
            state = .offline
            return
        }
        state = .verifying

        guard let origin = env.sharedItems.item(id: itemID)?.sharedOrigin,
              let expected = env.sharedItems.grant(forItem: itemID) else {
            state = .unavailable
            return
        }
        let zoneID = CKRecordZone.ID(zoneName: origin.zoneName, ownerName: origin.ownerName)
        let recipient = env.approvalRecipient
        let deadline = policy.grantVerificationDeadline
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        let live: Result<(id: String, epoch: UInt32), any Error>
        do {
            let grant = try await Self.withDeadline(deadline) {
                try await recipient.fetchGrant(zoneID: zoneID, grantId: expected.id, nowUnixMs: nowMs)
            }
            live = .success((grant.id, grant.epoch))
        } catch {
            live = .failure(error)
        }

        guard token == runToken else { return } // a newer run owns the state
        state = Self.outcome(expectedGrantId: expected.id, expectedEpoch: expected.epoch,
                             live: live)

        // Reconcile the projection where it can be stale — the fail-closed
        // state above is already committed either way.
        switch state {
        case .revoked:
            // Purges the item, the AutoFill cache, and the snapshot.
            if let key = env.session.vaultKey?.bytes {
                await env.sharedItems.refresh(vaultKey: key)
            }
        case .unavailable:
            // Live fetch SUCCEEDED but id/epoch drifted → our projection is
            // stale; refresh so the next gate pass verifies the new grant.
            if case .success = live, let key = env.session.vaultKey?.bytes {
                await env.sharedItems.refresh(vaultKey: key)
            }
        default:
            break
        }
    }

    /// Deadline wrapper: whichever finishes first wins; the loser is
    /// cancelled. A deadline hit surfaces as CancellationError → `unavailable`.
    private nonisolated static func withDeadline<T: Sendable>(
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
