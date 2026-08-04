import Foundation
import SwiftUI
import XCTest
@testable import Vaultify

/// What must survive a size-class flip (Split View drag, Stage Manager resize,
/// rotation across the compact boundary), which unmounts the ENTIRE unlocked shell
/// and every sheet on it:
///
/// - an unsaved editor draft and the ciphertext staged with it (the draft is never
///   on disk between backgrounds, so dropping it destroys typed secret material);
/// - the sidebar search field's ability to clear the detail column;
/// - the first keystroke typed before the detail column settles.
@MainActor
final class AdaptiveShellContinuityTests: XCTestCase {

    private let testKey = [UInt8](repeating: 0x2a, count: 32)

    private func makeStore() -> (store: UIStateStore, session: VaultSession, fileURL: URL) {
        let session = VaultSession(settings: SettingsStore())
        session.adoptUnlocked(key: testKey)
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "ui-state-tests-\(UUID().uuidString).enc")
        let store = UIStateStore(session: session, fileURL: fileURL)
        TestLifetimeRetainer.retain(session, store)
        return (store, session, fileURL)
    }

    private func makeDraft(title: String = "Bank") -> UIStateStore.DraftState {
        UIStateStore.DraftState(item: VaultItem(category: .login, title: title), isNew: true)
    }

    // MARK: Editor hand-back

    func testShellTeardownHandsTheDraftToTheNextShell() {
        let (store, _, _) = makeStore()
        store.editorDidMount()
        let draft = makeDraft()
        store.editorDraft = draft

        store.editorDidUnmount()
        store.handBackEditorSession()

        XCTAssertEqual(store.editorDraft, draft, "the live draft must not be dropped by a teardown")
        XCTAssertEqual(store.restoredDraft, draft, "the next shell presents it through this trigger")
        XCTAssertEqual(store.resumedEditorSession?.itemID, draft.item.id)
    }

    func testTheReceivingEditorClaimsTheSessionOnlyOnce() {
        let (store, _, _) = makeStore()
        let draft = makeDraft()
        store.editorDraft = draft
        store.handBackEditorSession()

        XCTAssertNotNil(store.claimResumedEditorSession(itemID: draft.item.id))
        XCTAssertNil(store.claimResumedEditorSession(itemID: draft.item.id),
                     "a second mount must not inherit an already-adopted session")
    }

    func testAnUnrelatedEditorCannotClaimTheSession() {
        let (store, _, _) = makeStore()
        let draft = makeDraft()
        store.editorDraft = draft
        store.handBackEditorSession()

        XCTAssertNil(store.claimResumedEditorSession(itemID: "some-other-item"))
        XCTAssertEqual(store.resumedEditorSession?.itemID, draft.item.id,
                       "a mismatch leaves the session pending for the editor it belongs to")
    }

    func testStagedCiphertextRidesTheHandoffInsteadOfBeingSwept() throws {
        let (store, session, _) = makeStore()
        let vaultStore = VaultStore(inMemory: true)
        let root = FileManager.default.temporaryDirectory
            .appending(path: "adaptive-shell-artifacts-\(UUID().uuidString)")
        let artifacts = ArtifactStore(session: session, store: vaultStore, directory: root)
        TestLifetimeRetainer.retain(vaultStore, artifacts)

        let staged = try artifacts.stage(data: Data("passport scan".utf8),
                                         filename: "passport.pdf", uti: "com.adobe.pdf")
        let draft = makeDraft()
        store.editorDraft = draft
        store.handBackEditorSession(stagedArtifacts: [staged])

        let claimed = store.claimResumedEditorSession(itemID: draft.item.id)
        XCTAssertEqual(claimed?.stagedArtifacts.map(\.id), [staged.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.fileURL.path),
                      "a handed-off attachment must still be committable after the flip")
    }

    func testUserClosingTheEditorEndsTheSession() {
        let (store, _, _) = makeStore()
        let draft = makeDraft()
        store.editorDraft = draft
        store.handBackEditorSession()

        store.finishEditorSession()

        XCTAssertNil(store.editorDraft)
        XCTAssertNil(store.restoredDraft)
        XCTAssertNil(store.resumedEditorSession)
    }

    func testRehydrateLeavesAMountedEditorAlone() {
        let (store, _, _) = makeStore()
        store.editorDidMount()
        store.editorDraft = makeDraft()

        store.rehydrateEditorIfNeeded()

        XCTAssertNil(store.restoredDraft, "the draft still has a host — re-presenting would duplicate it")
    }

    func testRehydrateArmsTheTriggerWhenNothingHostsTheDraft() {
        let (store, _, _) = makeStore()
        let draft = makeDraft()
        store.editorDidMount()
        store.editorDraft = draft
        store.editorDidUnmount()

        store.rehydrateEditorIfNeeded()

        XCTAssertEqual(store.restoredDraft, draft)
        XCTAssertEqual(store.resumedEditorSession?.itemID, draft.item.id)
    }

    func testRehydrateDoesNothingWithoutADraft() {
        let (store, _, _) = makeStore()
        store.rehydrateEditorIfNeeded()
        XCTAssertNil(store.restoredDraft)
        XCTAssertNil(store.resumedEditorSession)
    }

    func testUnmountCountNeverGoesNegative() {
        let (store, _, _) = makeStore()
        store.editorDidUnmount()
        store.editorDidUnmount()
        store.editorDidMount()

        store.editorDraft = makeDraft()
        store.editorDidUnmount()
        store.rehydrateEditorIfNeeded()

        XCTAssertNotNil(store.restoredDraft, "a stale positive count would hide the orphaned draft")
    }

    func testRecoveredDraftIsTreatedAsUnsavedWork() throws {
        let (store, session, fileURL) = makeStore()
        let draft = makeDraft(title: "Half typed")
        store.editorDraft = draft
        store.persist()

        let restored = UIStateStore(session: session, fileURL: fileURL)
        TestLifetimeRetainer.retain(restored)
        restored.restore()

        XCTAssertEqual(restored.restoredDraft?.id, draft.id)
        XCTAssertEqual(restored.restoredDraft?.item.title, draft.item.title)
        XCTAssertEqual(restored.resumedEditorSession?.itemID, draft.item.id,
                       "a cold-restored draft must survive a later flip too")
        try? FileManager.default.removeItem(at: fileURL)
    }

    func testWipeClearsTheHandoffState() {
        let (store, _, _) = makeStore()
        store.editorDidMount()
        store.editorDraft = makeDraft()
        store.handBackEditorSession()
        store.quickSheet = .generator

        store.wipe()

        XCTAssertNil(store.editorDraft)
        XCTAssertNil(store.restoredDraft)
        XCTAssertNil(store.resumedEditorSession)
        XCTAssertNil(store.quickSheet)
        XCTAssertEqual(store.mountedEditorCount, 0)
    }

    // MARK: Sidebar search

    func testClearingTheSidebarFieldReachesTheSearchDetail() {
        XCTAssertEqual(
            VaultSidebarView.searchEntry(for: "", showingSearchDetail: true),
            .query(""),
            "the detail column owns the results, title and empty state — it has to hear the clear")
    }

    func testClearingWithoutSearchOnScreenQueuesNothing() {
        XCTAssertEqual(
            VaultSidebarView.searchEntry(for: "", showingSearchDetail: false),
            .normal,
            "an empty query left pending would suppress the keyboard on the next Search entry")
    }

    func testTypingRetargetsTheSearchDetail() {
        XCTAssertEqual(VaultSidebarView.searchEntry(for: "gi", showingSearchDetail: false), .query("gi"))
        XCTAssertEqual(VaultSidebarView.searchEntry(for: "git", showingSearchDetail: true), .query("git"))
    }

    // MARK: Search entry

    func testFirstKeystrokeIsAppliedBeforeTheTabHasSettled() {
        let plan = SearchScreen.entryPlan(for: .query("g"), isActiveTab: false)
        XCTAssertEqual(plan.query, "g", "the detail column can appear before selectedTab is mirrored")
        XCTAssertTrue(plan.consumesEntry)
        XCTAssertTrue(plan.suppressesFocus, "the keyboard belongs to the sidebar's field")
        XCTAssertFalse(plan.requestsFocus)
    }

    func testAnEmptiedQueryClearsTheFieldWithoutStealingFocus() {
        let plan = SearchScreen.entryPlan(for: .query(""), isActiveTab: true)
        XCTAssertEqual(plan.query, "")
        XCTAssertTrue(plan.suppressesFocus)
        XCTAssertFalse(plan.requestsFocus)
    }

    func testPlainTabEntryRaisesTheKeyboardOnlyOnTheSearchTab() {
        let active = SearchScreen.entryPlan(for: .normal, isActiveTab: true)
        XCTAssertNil(active.query)
        XCTAssertTrue(active.requestsFocus)
        XCTAssertTrue(active.consumesEntry)

        let inactive = SearchScreen.entryPlan(for: .normal, isActiveTab: false)
        XCTAssertFalse(inactive.requestsFocus)
        XCTAssertFalse(inactive.consumesEntry, "a mode consumed off-tab would never reach Search")
    }

    // MARK: Search header chrome

    func testNavigationBarIsHiddenOnlyWhereTheTabBarCarriesTheSearchField() {
        XCTAssertTrue(FlushSearchHeaderChrome.hidesNavigationBar(
            horizontalSizeClass: .compact, searchFieldLivesInTabBar: true))
        XCTAssertFalse(FlushSearchHeaderChrome.hidesNavigationBar(
            horizontalSizeClass: .regular, searchFieldLivesInTabBar: true),
            "the split-view detail column renders the search field IN its navigation bar")
        XCTAssertFalse(FlushSearchHeaderChrome.hidesNavigationBar(
            horizontalSizeClass: nil, searchFieldLivesInTabBar: true))
        XCTAssertFalse(FlushSearchHeaderChrome.hidesNavigationBar(
            horizontalSizeClass: .compact, searchFieldLivesInTabBar: false))
    }
}
