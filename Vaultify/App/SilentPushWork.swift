import Foundation

/// Bridges the push delegate (created by the SwiftUI adaptor BEFORE
/// `AppEnvironment` exists) to the workers a silent content-available push
/// triggers. By the time a remote push can arrive the environment has been
/// built, so weak references registered at env init are sufficient; a nil
/// worker simply means there is no work to wait for.
///
/// Why the delegate waits at all: calling the fetch completion handler tells
/// iOS it may suspend the process, while the work behind a silent push is
/// several CloudKit round-trips. Returning the handler first races that
/// suspension — the refresh dies mid-flight, the "accepted" banner never
/// posts, and nothing retries until the next foreground.
@MainActor enum SilentPushWork {
    static weak var shareRefresher: OwnerShareRefresher?
    static weak var syncCoordinator: SyncCoordinator?

    /// Runs (or joins) the work a silent push of `kind` triggers and returns
    /// once a full pass has completed. User-visible alert pushes carry no
    /// fetch work and return immediately; the approval-response hint is
    /// consumed by a foreground requester UI, so it needs no background hold.
    static func awaitWork(for kind: AppPushKind) async {
        switch kind {
        case .shareAcceptance:
            await shareRefresher?.refreshAndWait()
        case .vaultRemoteChange:
            await syncCoordinator?.pullAndWait()
        case .approvalRequest, .approvalResponse, .inviteRendezvous:
            break
        }
    }
}
