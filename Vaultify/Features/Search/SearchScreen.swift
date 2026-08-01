import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Search tab — own NavigationStack + `.searchable`. With `Tab(role: .search)`
/// (iOS 18+) this is the native search surface (search field in the tab bar /
/// above the keyboard on iOS 26). Activating the search field on appear means both
/// the tab-bar search and the Home header magnifier drop straight into search.
///
/// Keyword search first (the 1Password split): browsing a Space, category, or tag
/// is a pushed `FilteredItemsScreen`/list elsewhere. A chip row adds quick
/// category narrowing + sort over the typed query — the same filter vocabulary
/// as the browse lists — while Space scoping stays implicit (never a chip the
/// user has to think about). The pool is the active persona's items (fail-closed
/// under strictAnonymous, INV-R03), and matching shared projections append as
/// their own section.
struct SearchScreen: View {
    @Environment(UIStateStore.self) private var uiState
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var searchPresented = false
    /// Guards the overlapping activation triggers below from racing each other.
    @State private var focusInFlight = false
    /// Set per entry — `true` suppresses the auto-keyboard (a pre-filled `.query` entry
    /// wants the results visible, not the keyboard).
    @State private var suppressFocus = false
    /// Process-lifetime: the FIRST activation rides the cold-launch layout storm
    /// (the app persists `selectedTab`, so it can restore straight onto Search),
    /// where an immediate focus request is silently dropped — that one waits
    /// longer. Later (warm) activations stay snappy. Resets only on app kill,
    /// which is exactly what "cold launch" means.
    @MainActor private static var didFirstActivation = false
    /// Deferred zoom source (Design DNA #5): shared between the result rows
    /// (`VaultItemRowLink`, via `ZoomTransitionSource`) and the pushed `ItemDetailScreen`
    /// (via `ZoomTransitionDestination`), both living inside this stack.
    @Namespace private var zoomNamespace

    var body: some View {
        @Bindable var uiState = uiState
        return NavigationStack(path: $uiState.searchPath) {
            SearchResultsList(query: search)
                // No title — the content (recents / results) starts flush at the top. On
                // iOS 26 the search field lives in the TAB BAR (Tab role: .search), so the
                // top nav bar is empty chrome whose INSET still grows/shrinks as the field
                // activates, dropping the content on dismiss — hide that nav bar there.
                // Pre-26 keeps the inline nav bar: the classic `.searchable` field renders
                // inside it, so hiding it would remove the search field.
                .navigationTitle("")
                .platformNavigationBarTitleDisplayMode(.inline)
                .modifier(FlushSearchHeaderChrome())
                .searchable(text: $search, isPresented: $searchPresented, prompt: "Search vault")
                // Count that a search happened — the term itself never leaves
                // the device (see the catalog note on `searchPerformed`).
                .onSubmit(of: .search) { AnalyticsEngine.shared.log(.searchPerformed) }
                .autocorrectionDisabled()
                .platformAutocapitalization(.never)
                .environment(\.vaultZoomNamespace, zoomNamespace)
                .vaultNavigationDestinations()
        }
        // `onAppear` fires once per tab entry (intra-stack pushes don't re-fire it), so it
        // is the single place the entry intent is applied. The extra focus triggers below
        // just retry the keyboard raise (cold launch fires `onAppear` too early; a
        // background/return needs a re-raise).
        .onAppear { handleEntry() }
        .analyticsScreen("search")
        // Live re-targeting while ALREADY showing: the iPad sidebar's search
        // field keeps sending `.query` per keystroke after the first one was
        // consumed by `handleEntry` — apply it in place, keyboard stays down.
        .onChange(of: uiState.searchEntry) { _, entry in
            if case .query(let q) = entry {
                search = q
                suppressFocus = true
                uiState.searchEntry = .normal
            }
        }
        .onChange(of: uiState.selectedTab) { _, tab in
            if tab == .search { requestSearchFocus() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { requestSearchFocus() }
        }
    }

    /// Apply the pending entry mode once, on tab entry: a `.query` entry pre-fills the
    /// field with the keyboard down; a plain tab open raises the keyboard. Consumes the
    /// mode back to `.normal`.
    private func handleEntry() {
        guard uiState.selectedTab == .search else { return }
        switch uiState.searchEntry {
        case .query(let q):
            search = q
            suppressFocus = true
        case .normal:
            suppressFocus = false
        }
        uiState.searchEntry = .normal
        requestSearchFocus()
    }

    /// Present + focus the search field, deferred past the layout pass. A native
    /// tab tap already focuses instantly (`role: .search`), so this mainly drives
    /// the programmatic paths — the Home magnifier and a cold restore onto Search —
    /// where an immediate request is dropped. The in-flight guard stops the
    /// overlapping triggers from clobbering each other; if an attempt didn't stick,
    /// a later trigger (next foreground / re-tap) retries.
    private func requestSearchFocus() {
        guard uiState.selectedTab == .search, !searchPresented, !focusInFlight, !suppressFocus else { return }
        focusInFlight = true
        let cold = !Self.didFirstActivation
        Self.didFirstActivation = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(cold ? 400 : 150))
            focusInFlight = false
            // Re-check `suppressFocus`: a query entry may have set it AFTER this task was
            // scheduled by an earlier trigger, so the keyboard stays down there.
            guard uiState.selectedTab == .search, !searchPresented, !suppressFocus else { return }
            searchPresented = true
        }
    }
}

/// Smart-search results over the active persona's items. Every space-separated
/// token must match the item's title/fields/tags; recognized operator keywords
/// (weak, reused, passkey, 2fa, category names…) filter structurally. Before
/// any query: recently used items. Shared-with-Me projections that match the
/// query append as their own section.
struct SearchResultsList: View {
    @Environment(AppEnvironment.self) private var env
    let query: String
    /// Quick category filter + sort (the chip row). The chip is an independent
    /// post-filter, NOT injected into `SearchOperators`: typed operator keywords
    /// keep their zero-result literal-text fallback, while a chip the user
    /// explicitly tapped always constrains the list.
    @State private var category: ItemCategory?
    @State private var sort = VaultSort()

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    /// The persona-wide pool, fail-closed for isolation: `.allSpaces` normally,
    /// the persona's own Space under strictAnonymous (INV-R03) — never a chip
    /// the user has to think about.
    private var scope: SpaceScope { env.repository.defaultSearchScope(currentSpaceId: nil) }

    /// Shared projections join the results only when cross-persona surfaces are
    /// allowed (mirrors the Items screen's pseudo-space gate) — never under
    /// strictAnonymous.
    private var showsShared: Bool {
        env.repository.showsSharedScope(base: env.settings.approvalModeEnabled || !env.sharedItems.items.isEmpty)
    }

    /// Local operator + free-text search. Operators (`SearchOperators.parse`)
    /// always filter WITHIN the persona pool — never widen it (see
    /// `VaultRepository.scopedItems(scope:)`).
    ///
    /// The operator reading must never make results WORSE than plain text
    /// search: keywords like "code", "security", or "mã" are common words the
    /// user may genuinely be searching for. When operators were recognized but
    /// produced nothing, the whole query re-runs as literal free text.
    private var results: [VaultItem] {
        var pool = keywordResults
        if let category { pool = pool.filter { $0.category == category } }
        return sort.apply(pool)
    }

    private var keywordResults: [VaultItem] {
        guard !trimmed.isEmpty else { return [] }
        let parsed = SearchOperators.parse(trimmed)
        let base: [VaultItem] = parsed.freeTextTokens.isEmpty
            ? env.repository.scopedItems(scope: scope)
            : env.repository.search(parsed.freeTextTokens.joined(separator: " "), scope: scope)
        guard !parsed.operators.isEmpty else { return base }
        let context = auditContext(for: base, operators: parsed.operators)
        let operated = base.filter { SearchOperators.matches($0, operators: parsed.operators, context: context) }
        // Zero-result fallback: same pool, whole query as literal text. Judged
        // on the CHIP-CONSTRAINED view: an operator reading that is non-empty
        // overall but empty within the active chip would otherwise show zero
        // results without ever trying the literal reading.
        let visible = category.map { c in operated.filter { $0.category == c } } ?? operated
        guard visible.isEmpty else { return operated }
        return env.repository.search(trimmed, scope: scope)
    }

    /// Shared projections matching the query. Projections aren't vault items or
    /// audited — only structural operators (category, has-TOTP) are meaningful;
    /// weak/reused/passkey simply never match (empty Context), which is correct:
    /// we never run a password audit over someone else's shared item.
    private var sharedResults: [VaultItem] {
        guard showsShared, !trimmed.isEmpty else { return [] }
        let parsed = SearchOperators.parse(trimmed)
        let operated = env.sharedItems.items.filter { item in
            SearchOperators.matches(item, operators: parsed.operators, context: .empty)
                && parsed.freeTextTokens.allSatisfy { item.searchText.contains($0) }
        }
        var base = operated
        // Fallback judged on the chip-constrained view, mirroring `keywordResults`.
        let visibleOperated = category.map { c in operated.filter { $0.category == c } } ?? operated
        if visibleOperated.isEmpty, !parsed.operators.isEmpty {
            let literalTokens = trimmed.lowercased().split(separator: " ").map(String.init)
            base = env.sharedItems.items.filter { item in
                literalTokens.allSatisfy { item.searchText.contains($0) }
            }
        }
        // Same chip semantics as the main section: an explicit chip filters
        // even the literal fallback.
        if let category { base = base.filter { $0.category == category } }
        return sort.apply(base)
    }

    /// Pre-query surface: what you touched last is usually what you came for.
    private var recents: [VaultItem] { env.repository.recentlyUsed(limit: 12) }

    /// Chip active with no query yet: browse that category across the scoped
    /// pool, so the chip means something before the user types.
    private var categoryBrowse: [VaultItem] {
        guard let category else { return [] }
        return sort.apply(env.repository.scopedItems(scope: scope).filter { $0.category == category })
    }

    /// Builds only the signals the recognized operators actually need, computed
    /// once per query over `pool` (already persona-filtered — never the whole
    /// vault). `PasswordAudit.analyze` here is therefore pool-relative: an item
    /// reused elsewhere but unique within this pool is not flagged "reused" —
    /// intentional, matches the scope-isolation invariant.
    private func auditContext(for pool: [VaultItem], operators: [SearchOperator]) -> SearchOperators.Context {
        let needsPasswordAudit = operators.contains { $0 == .weakPassword || $0 == .reusedPassword }
        let health = needsPasswordAudit ? PasswordAudit.analyze(pool) : .empty
        let needsPasskey = operators.contains(.hasPasskey)
        return SearchOperators.Context(
            weakItemIDs: Set(health.weak.map(\.itemID)),
            reusedItemIDs: Set(health.reused.map(\.itemID)),
            passkeyItemIDs: needsPasskey ? env.repository.passkeyItemIDs(in: pool) : [])
    }

    var body: some View {
        content
            // Pin to the top: otherwise the content rides down with the search field
            // when the keyboard is dismissed, leaving a gap at the top.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The chip row lives in the CONTENT area, not the toolbar: on iOS 26
            // the Search tab hides its nav bar (the field moved to the tab bar),
            // so a toolbar control would silently vanish there.
            .safeAreaInset(edge: .top, spacing: 0) { filterBar }
            .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.groupedBackground))
            // Keyboard dismissal rides on scroll (`.scrollDismissesKeyboard`) only. A
            // whole-surface `simultaneousGesture(TapGesture())` here used to cancel the
            // List's own cell selection, so result rows never pushed their detail.
    }

    @ViewBuilder private var content: some View {
        if trimmed.isEmpty {
            if category != nil {
                categoryBrowseList
            } else {
                recentsList
            }
        } else if results.isEmpty, sharedResults.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            resultsList
        }
    }

    /// Category chips + the compact sort menu. Chips never steal first
    /// responder, so the search-field focus choreography stays intact.
    private var filterBar: some View {
        HStack(spacing: Space.s2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    FilterChip(title: LocalizedStringResource("All").inAppLocalized, isSelected: category == nil) {
                        guard category != nil else { return }
                        category = nil
                        Haptics.tap()
                    }
                    ForEach(ItemCategory.allCases) { cat in
                        FilterChip(title: cat.title, isSelected: category == cat, icon: cat.iconAsset) {
                            category = category == cat ? nil : cat
                            Haptics.tap()
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
            }
            sortMenu
                .padding(.trailing, Space.gutter)
        }
        .padding(.vertical, Space.s1)
        // Opaque canvas under the pinned bar — the List's rows otherwise
        // scroll visibly through the safe-area inset.
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.groupedBackground))
    }

    private var sortMenu: some View {
        Menu {
            VaultSortPickers(sort: $sort)
        } label: {
            VaultIcon(Icons.sort, size: Metric.iconCompact)
                .themedForeground(.secondary)
                .frame(width: Metric.hitMin, height: Metric.hitMin)
                .contentShape(.rect)
        }
        // Plain glyph menu — macOS would otherwise draw a bordered pull-down button.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Sort"))
        // Haptic on the Menu, not its content: the content unmounts as the menu
        // closes and can miss the change that closed it.
        .onChange(of: sort) { Haptics.tap() }
    }

    /// Chip-only browse (no query yet): the chip's category across the pool.
    @ViewBuilder private var categoryBrowseList: some View {
        if let category {
            if categoryBrowse.isEmpty {
                ContentUnavailableView {
                    Label { Text("No items here") } icon: { VaultIcon(category.iconAsset, size: Metric.iconTileLarge) }
                }
            } else {
                List {
                    Section {
                        ForEach(categoryBrowse) { VaultItemRowLink(item: $0, highlight: "") }
                    } header: {
                        Text(category.title)
                    }
                }
                .platformInsetGroupedListStyle()
                .textCase(nil)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
    }

    /// Search mode: a flat, ranked list; matching shared projections follow in
    /// their own section (their rows are read-only pushes, like Shared with Me).
    private var resultsList: some View {
        List {
            if !results.isEmpty {
                Section {
                    ForEach(results) { VaultItemRowLink(item: $0, highlight: trimmed) }
                }
            }
            if !sharedResults.isEmpty {
                Section {
                    ForEach(sharedResults) { VaultItemRowLink(item: $0, highlight: trimmed) }
                } header: {
                    Text("Shared with Me")
                }
            }
        }
        .platformInsetGroupedListStyle()
        .textCase(nil)                 // section titles shown as-is, not uppercased
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    /// Empty-query surface: recently used items (the 1Password/Notes pattern —
    /// recents, not a browse dump; browsing lives in the pushed lists).
    @ViewBuilder private var recentsList: some View {
        if recents.isEmpty {
            ContentUnavailableView {
                Label { Text("Search vault") } icon: { VaultIcon(Icons.search, size: 48) }
            } description: {
                Text("Find items by name, field, or tag.")
            }
        } else {
            List {
                Section {
                    ForEach(recents) { VaultItemRowLink(item: $0, highlight: "") }
                } header: {
                    Text("Recent")
                }
            }
            .platformInsetGroupedListStyle()
            .textCase(nil)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }
}

/// Hides the top navigation bar on iOS 26, where the Search tab's field lives in
/// the TAB BAR (`Tab(role: .search)`) — the empty top nav bar there otherwise
/// reserves a variable inset that appears/disappears as the search field
/// activates, dropping the content on dismiss. Pre-26 keeps the nav bar
/// because the classic `.searchable` field renders inside it. Uses a plain runtime
/// `#available` (no `#if compiler` guard): `.toolbar(.hidden:)` is an iOS-16 API, so
/// this compiles on any Xcode and the fix ships in CI/TestFlight builds too.
private struct FlushSearchHeaderChrome: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        // iOS-only by intent (the tab-bar search field exists there); macOS
        // keeps its normal chrome — and `.navigationBar` isn't a macOS
        // toolbar placement anyway.
        #if os(iOS)
        if #available(iOS 26, *) {
            content.toolbar(.hidden, for: .navigationBar)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
