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
            VaultSidebarList(selection: Binding(
                get: { uiState.sidebarSelection },
                set: { uiState.sidebarSelection = $0 ?? .section(.home) }
            ))
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
        case .profile:
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
        }
    }
}
