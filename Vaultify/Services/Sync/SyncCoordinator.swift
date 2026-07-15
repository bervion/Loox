import Foundation

/// Decides WHEN sync runs (the `CloudSyncService` decides HOW): immediately on
/// unlock / foreground-activate / manual "Sync Now", and debounced after local
/// mutations (repository posts `.vaultLocalMutation`) so a burst of edits becomes
/// one push instead of many.
///
/// Single-flight: while a sync is in progress, further requests coalesce into ONE
/// follow-up run — combined with `VaultStore.markSynced`'s snapshot guard, an edit
/// made during an in-flight push stays dirty and is picked up by the follow-up
/// instead of being silently un-dirtied.
@MainActor final class SyncCoordinator {
    private let cloudSync: CloudSyncService
    private let repository: VaultRepository
    private let settings: SettingsStore
    /// Mirrors the recovery-wrapped Vault Key to CloudKit after each sync (cheap
    /// fingerprint no-op when unchanged) so a new device can join by Emergency Kit.
    private let escrow = VaultKeyEscrowService()
    /// Registers the silent-push zone subscription (near-real-time sync).
    private let pushService = SyncPushService()
    /// Publishes this device to the owner device registry after each successful sync, so
    /// peers appear in Profile › Devices without opening the screen (best-effort, list-only).
    private let deviceRegistry: DeviceRegistryService

    private var debounceTask: Task<Void, Never>?
    /// Shared coalescing primitive (same semantics as the previous inline
    /// inFlight/followUp pair; also used by the approval coordinator).
    private let singleFlight = SingleFlight()
    private var observers: [NSObjectProtocol] = []

    /// Delay after the last local mutation before pushing (batches edit bursts).
    private static let mutationDebounce: Duration = .seconds(3)

    init(cloudSync: CloudSyncService, repository: VaultRepository, settings: SettingsStore) {
        self.cloudSync = cloudSync
        self.repository = repository
        self.settings = settings
        self.deviceRegistry = DeviceRegistryService(settings: settings)
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .vaultLocalMutation, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleDebouncedSync() }
        })
        // A silent CloudKit push means another device already changed the vault —
        // pull immediately (single-flight coalesces push bursts into one run).
        observers.append(center.addObserver(
            forName: .vaultRemoteChangePush, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settings.iCloudSyncEnabled else { return }
                self.syncNow()
            }
        })
    }

    /// Immediate sync — unlock, return-to-foreground, or the manual settings button.
    func syncNow() {
        debounceTask?.cancel()
        debounceTask = nil
        Task { await runSync() }
    }

    /// Awaitable pull for the background silent-push path: the push delegate
    /// holds the system fetch completion handler until this returns so iOS
    /// keeps the process alive for the CloudKit round-trip instead of
    /// suspending it mid-pull (see `OwnerShareRefresher.refreshAndWait`).
    /// No-op when vault sync is off. Joins any in-flight run via the
    /// single-flight, returning only after a full pass completes.
    func pullAndWait() async {
        guard CloudSyncService.isConfigured, settings.iCloudSyncEnabled else { return }
        await runSync()
    }

    /// Debounced sync after a local mutation.
    private func scheduleDebouncedSync() {
        guard CloudSyncService.isConfigured, settings.iCloudSyncEnabled else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.mutationDebounce)
            guard !Task.isCancelled else { return }
            await self?.runSync()
        }
    }

    private func runSync() async {
        await singleFlight.run { [cloudSync, repository] in
            await cloudSync.sync(reload: { repository.reloadAfterRemoteSync() })
        }
        if settings.iCloudSyncEnabled, case .success = cloudSync.status {
            await escrow.pushRecoveryEnvelopeIfNeeded()
            await pushService.ensureSubscribedIfNeeded()
            await deviceRegistry.publish()
        }
    }
}
