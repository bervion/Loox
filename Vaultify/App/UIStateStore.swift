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

    /// An unsaved editor session handed to a NEW mount of the item editor — either
    /// recovered from disk on cold launch, or carried across a shell remount (a
    /// size-class flip tears down the whole shell, sheets included). The receiving
    /// editor claims it once and then treats its content as unsaved work, so a
    /// second remount hands the same session on again.
    ///
    /// `stagedArtifacts` are that session's encrypted-but-uncommitted attachment
    /// imports. Their DEKs live only here, in memory — the on-disk `Snapshot`
    /// carries the draft alone — and a handoff nobody claims leaves staging files
    /// that `ArtifactStore.reconcile()` sweeps at the next unlock.
    struct ResumedEditorSession {
        let itemID: String
        let stagedArtifacts: [StagedArtifact]
    }

    /// A quick-action sheet owned by the SHELL rather than by one layout. Held here
    /// so both shells present it from `vaultShellBehaviors()`: a size-class flip
    /// destroys the layout's own `@State`, which used to drop the sheet outright.
    enum QuickSheet: String, Identifiable {
        case generator
        case totpCodes
        var id: String { rawValue }
    }

    /// iPad/Mac sidebar selection. A section mirrors `selectedTab`; a space points at a
    /// folder id; profile opens the persona detail; settings opens the settings detail.
    enum SidebarSelection: Hashable {
        case section(VaultTab)
        case space(String)
        case profile
        case settings
    }

    var selectedTab: VaultTab = .home

    /// Live sidebar selection (iPad/Mac). Deliberately NOT part of the on-disk `Snapshot`:
    /// it's derived from `selectedTab` and reconstructed on every layout appearance, so a
    /// Stage-Manager size-class flip never leaves the detail column empty (decoupled from the
    /// once-per-launch cold restore). Seeded from the restored `selectedTab` on cold launch.
    var sidebarSelection: SidebarSelection = .section(.home)

    /// How the Search surface should open on its NEXT activation. Ephemeral — deliberately
    /// NOT part of the on-disk `Snapshot`: `.normal` (a plain Search-tab tap) raises the
    /// keyboard; `.query` pre-fills the field. `SearchScreen` consumes it back to `.normal`
    /// on entry, so a later plain tab tap is always normal.
    enum SearchEntry: Equatable {
        case normal
        /// Open Search pre-filled with a query (the iPad/Mac sidebar's search
        /// field re-sends this per keystroke): results render immediately,
        /// keyboard stays down so the list is what the user sees.
        case query(String)
    }
    var searchEntry: SearchEntry = .normal

    /// Quick-action sheet currently up (generator / 2FA codes), or nil.
    var quickSheet: QuickSheet?

    /// Per-tab navigation depth for the REGULAR-width shell and the on-disk snapshot.
    ///
    /// Scope of the guarantee, deliberately narrow: compact width pushes through the
    /// UIKit shell (`VaultUINavShell` / `AppNavigator`), which never writes these paths,
    /// so a compact→regular flip keeps the SELECTION but starts the new column at its
    /// root. Regular→compact restores depth because these paths were the source there.
    /// Mirroring the UIKit stack into this store is explicitly out of scope — it would
    /// rewrite the app's highest-risk surface to preserve a scroll position.
    var homePath = NavigationPath()
    var itemsPath = NavigationPath()
    var searchPath = NavigationPath()
    var watchtowerPath = NavigationPath()
    /// Live capture of the currently-open editor's draft. Written by the mounted editor
    /// and read by `persist()`; it is NOT a presentation trigger (the editor is already
    /// on screen when this is set). Cleared only when the USER closes the editor — a
    /// shell teardown hands it on instead (see `handBackEditorSession`).
    var editorDraft: DraftState?
    /// One-shot presentation trigger for a draft the user did not close: recovered from
    /// a previous launch (`restore()`), or carried across a shell remount
    /// (`handBackEditorSession` / `rehydrateEditorIfNeeded`). Both shells bind a sheet
    /// to it in `vaultShellBehaviors()`. Kept separate from `editorDraft` so capturing
    /// a normally-opened editor never re-presents a duplicate.
    var restoredDraft: DraftState?
    /// Set alongside `restoredDraft`; claimed by the editor mount that adopts it.
    private(set) var resumedEditorSession: ResumedEditorSession?
    /// How many item editors are on screen. A size-class flip unmounts one and mounts
    /// the replacement, so "no editor mounted while a draft exists" is what identifies
    /// a draft that lost its host.
    private(set) var mountedEditorCount = 0

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
        if let draft = snapshot.draft {
            // A recovered draft is unsaved work even though it equals its own
            // baseline: the editor that adopts it must guard it like typed changes.
            resumedEditorSession = ResumedEditorSession(itemID: draft.item.id, stagedArtifacts: [])
        }
    }

    // MARK: Editor session lifecycle

    /// An item editor came on screen.
    func editorDidMount() { mountedEditorCount += 1 }

    /// An item editor left the screen. Never negative — a mount that somehow
    /// skipped its pairing must not make the store think an editor is still up.
    func editorDidUnmount() { mountedEditorCount = max(0, mountedEditorCount - 1) }

    /// The USER closed the editor (saved, or confirmed discard, or dismissed an
    /// untouched one). Nothing is left to hand back.
    func finishEditorSession() {
        editorDraft = nil
        restoredDraft = nil
        resumedEditorSession = nil
    }

    /// The editor's HOST went away while unsaved work was still in it — a size-class
    /// flip (Split View resize, Stage Manager, rotation across the compact boundary)
    /// unmounts the whole shell and its sheets. Re-arm the shared presentation trigger
    /// so the shell that replaces it puts the draft, and the ciphertext staged with it,
    /// straight back on screen.
    ///
    /// Returns whether the session was taken on. `false` means there was no draft to
    /// carry — the caller still owns its staged ciphertext and must roll it back
    /// rather than leave it in the staging directory.
    @discardableResult
    func handBackEditorSession(stagedArtifacts: [StagedArtifact] = []) -> Bool {
        guard let draft = editorDraft else { return false }
        resumedEditorSession = ResumedEditorSession(itemID: draft.item.id,
                                                    stagedArtifacts: stagedArtifacts)
        restoredDraft = draft
        return true
    }

    /// Live (non-cold-launch) hand-back, from the shell's own appearance: a draft
    /// exists but nothing is hosting it. Belt to `handBackEditorSession`'s braces —
    /// the incoming shell can appear BEFORE the outgoing editor reports its unmount,
    /// and either order has to end with the draft on screen. A draft that already has
    /// a pending trigger, or an editor still mounted, is left alone.
    func rehydrateEditorIfNeeded() {
        guard mountedEditorCount == 0, restoredDraft == nil, editorDraft != nil else { return }
        handBackEditorSession()
    }

    /// Adopt the handed-back session for `itemID`, once. A mismatch leaves the session
    /// pending: the editor it belongs to may not be the one that just mounted.
    func claimResumedEditorSession(itemID: String) -> ResumedEditorSession? {
        guard let session = resumedEditorSession, session.itemID == itemID else { return nil }
        resumedEditorSession = nil
        return session
    }

    /// Drop in-memory state and delete the on-disk snapshot (vault erase / reset).
    func wipe() {
        selectedTab = .home
        sidebarSelection = .section(.home)
        quickSheet = nil
        homePath = NavigationPath()
        itemsPath = NavigationPath()
        searchPath = NavigationPath()
        watchtowerPath = NavigationPath()
        editorDraft = nil
        restoredDraft = nil
        resumedEditorSession = nil
        mountedEditorCount = 0
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
