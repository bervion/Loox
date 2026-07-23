import SwiftUI

/// Live source of truth for restorable UI state — the selected tab, each tab's
/// navigation depth, and any in-progress (unsaved) editor draft.
///
/// The snapshot is sealed with the **Vault Key** (AES-256-GCM) and written to the
/// app's Documents directory with complete file protection, so nav metadata (item
/// ids, folder ids) and unsaved secret drafts never touch plaintext storage. It is
/// saved on background (before the vault locks, while the key is still in memory)
/// and re-applied after the next unlock.
@MainActor @Observable final class UIStateStore {
    /// A pending editor draft captured while the item editor was open. `isNew`
    /// distinguishes a create (→ `.draft`) from an edit of an existing item (→ `.edit`).
    struct DraftState: Codable, Identifiable, Equatable {
        var item: VaultItem
        var isNew: Bool
        var id: String { item.id }
    }

    /// iPad/Mac sidebar selection. A section mirrors `selectedTab`; a space points at a
    /// folder id; profile opens the profile/settings detail.
    enum SidebarSelection: Hashable {
        case section(VaultTab)
        case space(String)
        case profile
    }

    var selectedTab: VaultTab = .home

    /// Live sidebar selection (iPad/Mac). Deliberately NOT part of the on-disk `Snapshot`:
    /// it's derived from `selectedTab` and reconstructed on every layout appearance, so a
    /// Stage-Manager size-class flip never leaves the detail column empty (decoupled from the
    /// once-per-launch cold restore). Seeded from the restored `selectedTab` on cold launch.
    var sidebarSelection: SidebarSelection = .section(.home)

    /// How the Search surface should open on its NEXT activation. Ephemeral — deliberately
    /// NOT part of the on-disk `Snapshot`: `.normal` (the Search tab) resets the scope to
    /// its default (All Spaces) and raises the keyboard; `.browse` (Home "See all") seeds the
    /// scope from the chosen Home Space and does NOT raise the keyboard. `SearchScreen`
    /// consumes it back to `.normal` on entry, so a later plain tab tap is always normal.
    enum SearchEntry: Equatable {
        case normal
        case browse(spaceId: String?)
        /// Open Search pre-filled with a query (the Loox hub's stat tiles jump
        /// into "show me those items"): results render immediately, keyboard
        /// stays down so the list is what the user sees.
        case query(String)
    }
    var searchEntry: SearchEntry = .normal

    var homePath = NavigationPath()
    var itemsPath = NavigationPath()
    var searchPath = NavigationPath()
    var watchtowerPath = NavigationPath()
    /// Live capture of the currently-open editor's draft, for the snapshot only.
    /// NOT a presentation trigger — the editor is already on screen when this is set.
    var editorDraft: DraftState?
    /// One-shot presentation trigger for a draft recovered from a previous launch.
    /// Set only by `restore()`; `MainTabView` binds a sheet to it. Kept separate from
    /// `editorDraft` so capturing a normally-opened editor never re-presents a duplicate.
    var restoredDraft: DraftState?

    private let session: VaultSession
    private let fileURL: URL
    /// Restore runs at most once per process launch. A warm re-lock (foreground
    /// inactivity / shake) leaves this store's live values intact, so re-applying the
    /// on-disk snapshot there would wrongly rewind the user; only a cold launch (fresh
    /// store, default values) should adopt the snapshot.
    private var hasRestored = false

    init(session: VaultSession, fileURL: URL? = nil) {
        self.session = session
        self.fileURL = fileURL ?? Self.productionFileURL
    }

    // MARK: Snapshot model

    /// Codable on-disk form. Each path is the JSON of `NavigationPath.CodableRepresentation`
    /// (nil when the path holds a non-Codable element, e.g. Watchtower's category — that
    /// depth simply isn't restored, which is acceptable for a report screen).
    private struct Snapshot: Codable {
        var selectedTab: Int
        var homePath: Data?
        var itemsPath: Data?
        var searchPath: Data?
        var watchtowerPath: Data?
        var draft: DraftState?
    }

    // MARK: Persist / restore

    /// Seal the current UI state under the Vault Key. No-op when locked (no key).
    /// Call this BEFORE `session.lock()` on background so the key is still present.
    func persist() {
        guard let key = session.vaultKey else { return }
        let snapshot = Snapshot(
            selectedTab: selectedTab.rawValue,
            homePath: Self.encode(homePath),
            itemsPath: Self.encode(itemsPath),
            searchPath: Self.encode(searchPath),
            watchtowerPath: Self.encode(watchtowerPath),
            draft: editorDraft)
        guard let plaintext = try? JSONEncoder().encode(snapshot),
              let sealed = try? AESGCM.seal(plaintext, key: key) else { return }
        try? sealed.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    /// Decrypt and apply the last snapshot. No-op when locked or when nothing was saved.
    func restore() {
        guard !hasRestored else { return }
        hasRestored = true
        guard let key = session.vaultKey,
              let sealed = try? Data(contentsOf: fileURL),
              let plaintext = try? AESGCM.open(sealed, key: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: plaintext) else { return }
        selectedTab = VaultTab(rawValue: snapshot.selectedTab) ?? .home
        sidebarSelection = .section(selectedTab)
        homePath = Self.decode(snapshot.homePath)
        itemsPath = Self.decode(snapshot.itemsPath)
        searchPath = Self.decode(snapshot.searchPath)
        watchtowerPath = Self.decode(snapshot.watchtowerPath)
        // Present via the one-shot trigger; the presented editor re-populates
        // `editorDraft` (via its capture) so a re-background keeps persisting it.
        editorDraft = snapshot.draft
        restoredDraft = snapshot.draft
    }

    /// Drop in-memory state and delete the on-disk snapshot (vault erase / reset).
    func wipe() {
        selectedTab = .home
        sidebarSelection = .section(.home)
        homePath = NavigationPath()
        itemsPath = NavigationPath()
        searchPath = NavigationPath()
        watchtowerPath = NavigationPath()
        editorDraft = nil
        restoredDraft = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: Helpers

    private static let productionFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ui-state.enc")
    }()

    private static func encode(_ path: NavigationPath) -> Data? {
        guard let representation = path.codable else { return nil }
        return try? JSONEncoder().encode(representation)
    }

    private static func decode(_ data: Data?) -> NavigationPath {
        guard let data,
              let representation = try? JSONDecoder().decode(
                NavigationPath.CodableRepresentation.self, from: data) else {
            return NavigationPath()
        }
        return NavigationPath(representation)
    }
}
