import SwiftUI

/// Composition root: owns the long-lived stores/services and wires them
/// together. Injected into the SwiftUI environment.
@MainActor @Observable final class AppEnvironment {
    let settings: SettingsStore
    let theme: ThemeStore
    let session: VaultSession
    let store: VaultStore
    let repository: VaultRepository
    let clipboard: ClipboardService
    let cloudSync: CloudSyncService
    let faviconService: FaviconService
    let attachmentStore: AttachmentStore
    /// Restorable UI state (selected tab, per-tab nav depth, in-progress editor draft),
    /// sealed under the Vault Key. Saved on background, re-applied after unlock.
    let uiState: UIStateStore

    /// A 2FA login imported from an `otpauth://` link/QR, awaiting the editor. Presented once the
    /// vault is unlocked; cleared when the editor dismisses.
    var pendingTOTPImport: VaultItem?

    init() {
        let settings = SettingsStore()
        let session = VaultSession(settings: settings)
        let store = VaultStore()
        self.settings = settings
        self.theme = ThemeStore()
        self.session = session
        self.store = store
        self.repository = VaultRepository(store: store, session: session)
        self.clipboard = ClipboardService(settings: settings)
        self.cloudSync = CloudSyncService(store: store, settings: settings)
        self.faviconService = FaviconService()
        self.attachmentStore = AttachmentStore(session: session)
        self.uiState = UIStateStore(session: session)
    }

    /// Sync with iCloud if enabled, then refresh the decrypted cache.
    func syncNow() {
        Task { await cloudSync.sync(reload: { [repository] in repository.reload() }) }
    }

    /// Wipe all data and key material (Settings → Erase Vault).
    func eraseEverything() {
        repository.clear()
        try? store.eraseAll()
        uiState.wipe()
        session.resetVault()
    }
}
