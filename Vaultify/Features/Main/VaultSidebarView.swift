import SwiftUI

/// The regular-width (iPad + Mac) unlocked shell: a `NavigationSplitView` with the
/// sidebar list and a detail column that hosts the selected section's existing screen.
///
/// Two-column by design: each section screen (`HomeScreen`/`ItemsScreen`/…) already owns
/// its own `NavigationStack` + `vaultNavigationDestinations()`, so list→detail pushes stay
/// inside that column and behave exactly as on iPhone — no double-navigation. Shared shell
/// behaviors come from `vaultShellBehaviors()`, the same modifier `MainTabView` applies.
struct VaultSidebarView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(UIStateStore.self) private var uiState
    /// Sidebar-integrated vault search (iPad-Settings idiom, owner 260723):
    /// typing drives the Search detail live via `SearchEntry.query`.
    @State private var sidebarSearch = ""

    // Quick Actions live in the sidebar at regular width (Home hides its own grid
    // there), so this layout owns their sheets — anchored on the split view itself,
    // not on a list row, so a selection change can't strand a presentation.
    @State private var editorTarget: EditorTarget?
    @State private var showItemTypePicker = false
    @State private var pendingNewCategory: ItemCategory?
    @State private var showGenerator = false
    @State private var showTotpList = false
    /// Cached Watchtower issue count for the Security row's badge — recomputed on
    /// appear and when the item set changes, never per render (`PasswordAudit.analyze`
    /// is far too costly for that). Mirrors `HomeScreen`'s own cache.
    @State private var watchtowerIssueCount = 0

    /// Always-visible field on iPad (`navigationBarDrawer` is iOS-only);
    /// macOS uses the native sidebar placement, which is always visible too.
    private static var sidebarSearchPlacement: SearchFieldPlacement {
        #if os(macOS)
        .sidebar
        #else
        .navigationBarDrawer(displayMode: .always)
        #endif
    }

    var body: some View {
        @Bindable var uiState = uiState
        // Permanent sidebar (iPad-Settings idiom, owner 260723): visibility pinned
        // to `.all` and the system toggle removed — the sidebar IS the navigation,
        // never chrome to dismiss. Narrow multitasking widths don't fight this:
        // compact width switches the whole shell to `MainTabView` upstream.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            // Bridge the non-optional model to the optional binding `List(selection:)` needs;
            // a nil clear (e.g. deselect) falls back to Home so the detail column is never empty.
            VaultSidebarList(
                selection: Binding(
                    get: { uiState.sidebarSelection },
                    set: { uiState.sidebarSelection = $0 ?? .section(.home) }
                ),
                watchtowerIssueCount: watchtowerIssueCount,
                // Unfiltered: the sidebar is above the Home Space filter, so its
                // count is the whole vault's 2FA logins.
                totpCount: env.repository.totpItems(folder: nil).count,
                onAddItem: { showItemTypePicker = true },
                onGeneratePassword: { showGenerator = true },
                onOpenTotpCodes: { showTotpList = true })
            // No brand title (owner 260723): like iPad Settings, the sidebar
            // opens straight with the search field and the avatar row.
            .navigationTitle("")
            .searchable(text: $sidebarSearch,
                        placement: Self.sidebarSearchPlacement,
                        prompt: "Search vault")
            // Every keystroke re-targets the Search detail with the live query;
            // `SearchScreen` consumes `.query` both on entry and in place.
            .onChange(of: sidebarSearch) { _, query in
                guard !query.isEmpty else { return }
                uiState.searchEntry = .query(query)
                if uiState.sidebarSelection != .section(.search) {
                    uiState.sidebarSelection = .section(.search)
                }
            }
            // Apple-standard sidebar proportions (default collapses too narrow on macOS).
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail(for: uiState.sidebarSelection)
        }
        // Balanced: portrait keeps both columns on screen instead of sliding the
        // sidebar over the detail — matches the pinned-visible contract above.
        .navigationSplitViewStyle(.balanced)
        // No tint override (owner 260723): the sidebar renders the SYSTEM
        // default — accent selection, sidebar material/Liquid Glass — instead
        // of the custom primary-tinted look.
        .vaultShellBehaviors()
        // A size-class flip re-mounts this view. The compact tab shell only mutates
        // `selectedTab` (it never touches `sidebarSelection`), so reconcile on appear or a
        // section changed while compact would be stranded here (red-team #18). This is what
        // makes the "reconstructed on every layout appearance" guarantee real.
        .onAppear(perform: reconcileSelection)
        // Picking a section mirrors it into `selectedTab` (persisted + keeps the tab shell in
        // sync if the size class flips); any selection counts as activity for auto-lock.
        .onChange(of: uiState.sidebarSelection) { _, selection in
            if case .section(let tab) = selection { uiState.selectedTab = tab }
            env.session.registerActivity()
        }
        // A `.vaultSwitchTo*` notification (handled in the shared shell) mutates `selectedTab`;
        // reflect that back into the sidebar so cross-section jumps work in this layout too.
        .onChange(of: uiState.selectedTab) { _, tab in
            if uiState.sidebarSelection != .section(tab) {
                uiState.sidebarSelection = .section(tab)
            }
        }
        // Quick Actions (see the state block above). Same flows Home's grid drives.
        .task { recomputeWatchtowerCount() }
        .onChange(of: env.repository.items.count) { recomputeWatchtowerCount() }
        .sheet(item: $editorTarget) { ItemEditorScreen(target: $0) }
        // Item-type picker → present the editor once it finishes dismissing.
        .sheet(isPresented: $showItemTypePicker, onDismiss: {
            if let category = pendingNewCategory {
                pendingNewCategory = nil
                editorTarget = .new(category)
            }
        }) {
            ItemTypePickerSheet { pendingNewCategory = $0; showItemTypePicker = false }
        }
        .sheet(isPresented: $showGenerator) { GeneratorScreen() }
        .sheet(isPresented: $showTotpList) { TotpListScreen() }
    }

    /// Security issues (weak + reused + missing 2FA) for the sidebar's Security badge.
    /// Scoped to the ACTIVE persona, exactly like the Watchtower screen and Home's
    /// cache, so badge and screen never disagree.
    private func recomputeWatchtowerCount() {
        let health = PasswordAudit.analyze(env.repository.activePersonaItems)
        watchtowerIssueCount = health.weak.count + health.reused.count + health.missing2FA.count
    }

    /// Bring `sidebarSelection` back in step with live state when this layout (re)appears.
    private func reconcileSelection() {
        switch uiState.sidebarSelection {
        case .section:
            // Adopt the current tab (it may have advanced in the compact shell).
            if uiState.sidebarSelection != .section(uiState.selectedTab) {
                uiState.sidebarSelection = .section(uiState.selectedTab)
            }
        case .space(let folderId):
            // Drop a selection whose folder was deleted while away → fall back to the tab.
            if !env.repository.folders.contains(where: { $0.id == folderId }) {
                uiState.sidebarSelection = .section(uiState.selectedTab)
            }
        case .profile, .settings:
            break
        }
    }

    @ViewBuilder
    private func detail(for selection: UIStateStore.SidebarSelection) -> some View {
        switch selection {
        case .section(.home): HomeScreen()
        case .section(.items): ItemsScreen()
        case .section(.watchtower): WatchtowerScreen()
        case .section(.search): SearchScreen()
        case .space(let folderId):
            NavigationStack {
                FolderItemsScreen(folderId: folderId)
                    .vaultNavigationDestinations()
            }
        case .profile:
            // Carries the shared destinations: the Loox hub pushes item lists
            // (category/passkey) whose rows push item detail in this stack.
            NavigationStack { ProfileScreen().vaultNavigationDestinations() }
        case .settings:
            // Settings drives its own `NavigationLink` children, so it only needs
            // a stack — no shared route destinations.
            NavigationStack { SettingsScreen() }
        }
    }
}
