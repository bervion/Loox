import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Search tab — own NavigationStack + `.searchable`. With `Tab(role: .search)`
/// (iOS 18+) this is the native search surface (search field in the tab bar /
/// above the keyboard on iOS 26). Activating the search field on appear means both
/// the tab-bar search and the Home header magnifier drop straight into search.
struct SearchScreen: View {
    @Environment(UIStateStore.self) private var uiState
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var searchPresented = false
    /// Guards the overlapping activation triggers below from racing each other.
    @State private var focusInFlight = false
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
                .navigationTitle("Search")
                .searchable(text: $search, isPresented: $searchPresented, prompt: "Search vault")
                .autocorrectionDisabled()
                .platformAutocapitalization(.never)
                .environment(\.vaultZoomNamespace, zoomNamespace)
                .vaultNavigationDestinations()
        }
        // Raise the search field + keyboard whenever Search becomes the active
        // surface. Several triggers because a lone `onAppear` fires too early on a
        // cold launch that restores straight onto this tab.
        .onAppear { requestSearchFocus() }
        .onChange(of: uiState.selectedTab) { _, tab in
            if tab == .search { requestSearchFocus() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { requestSearchFocus() }
        }
    }

    /// Present + focus the search field, deferred past the layout pass. A native
    /// tab tap already focuses instantly (`role: .search`), so this mainly drives
    /// the programmatic paths — the Home magnifier and a cold restore onto Search —
    /// where an immediate request is dropped. The in-flight guard stops the
    /// overlapping triggers from clobbering each other; if an attempt didn't stick,
    /// a later trigger (next foreground / re-tap) retries.
    private func requestSearchFocus() {
        guard uiState.selectedTab == .search, !searchPresented, !focusInFlight else { return }
        focusInFlight = true
        let cold = !Self.didFirstActivation
        Self.didFirstActivation = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(cold ? 400 : 150))
            focusInFlight = false
            guard uiState.selectedTab == .search, !searchPresented else { return }
            searchPresented = true
        }
    }
}

/// Smart-search results, scoped to a Space. Search defaults to the Space you
/// were last in (seeded from the persisted Home selection); a chip row widens it
/// to All Spaces or the Shared-with-Me projection. Every space-separated token
/// must match the item's title/fields/tags.
struct SearchResultsList: View {
    @Environment(AppEnvironment.self) private var env
    let query: String

    /// Ephemeral per-session scope (never persisted). Seeded once on appear from
    /// the current Home Space.
    @State private var scope: SpaceScope = .allSpaces
    @State private var didSeedScope = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    /// The Space the user is currently in, if it still exists — the default
    /// search scope. nil when Home is on "All Spaces" or the Space was deleted.
    private var currentSpaceId: String? {
        let key = env.repository.activePersona?.id ?? PersonaID.placeholder
        guard let saved = env.settings.lastSelectedSpace(persona: key),
              env.repository.activePersonaSpaces.contains(where: { $0.id == saved }) else { return nil }
        return saved
    }

    /// Shared-with-Me is offered as a scope only when there is something to show
    /// (mirrors the Items screen's pseudo-space gate) AND the active persona's
    /// isolation allows cross-persona surfaces — never under strictAnonymous.
    private var showsSharedScope: Bool {
        env.repository.showsSharedScope(base: env.settings.approvalModeEnabled || !env.sharedItems.items.isEmpty)
    }

    private var availableScopes: [SpaceScope] {
        var out: [SpaceScope] = []
        if let id = currentSpaceId { out.append(.thisSpace(id: id)) }
        if env.repository.allSpacesSearchAllowed { out.append(.allSpaces) }
        if showsSharedScope { out.append(.sharedWithMe) }
        return out
    }

    /// Local operator + free-text search. Operators (`SearchOperators.parse`)
    /// always filter WITHIN whatever `scope` already resolved — never widen it
    /// (see `VaultRepository.scopedItems(scope:)`).
    ///
    /// The operator reading must never make results WORSE than plain text
    /// search: keywords like "code", "security", or "mã" are common words the
    /// user may genuinely be searching for. When operators were recognized but
    /// produced nothing, the whole query re-runs as literal free text.
    private var results: [VaultItem] {
        let parsed = SearchOperators.parse(trimmed)
        switch scope {
        case .sharedWithMe:
            // No query → list everything in scope (the tab opens showing all items).
            guard !parsed.freeTextTokens.isEmpty || !parsed.operators.isEmpty else { return env.sharedItems.items }
            // Shared projections aren't vault items/audited — only structural
            // operators (category, has-TOTP) are meaningful here; weak/reused/
            // passkey simply never match (empty Context), which is correct: we
            // never run a password audit over someone else's shared item.
            let operated = env.sharedItems.items.filter { item in
                SearchOperators.matches(item, operators: parsed.operators, context: .empty)
                    && parsed.freeTextTokens.allSatisfy { item.searchText.contains($0) }
            }
            guard operated.isEmpty, !parsed.operators.isEmpty else { return operated }
            let literalTokens = trimmed.lowercased().split(separator: " ").map(String.init)
            return env.sharedItems.items.filter { item in
                literalTokens.allSatisfy { item.searchText.contains($0) }
            }
        case .thisSpace, .allSpaces:
            let base: [VaultItem] = parsed.freeTextTokens.isEmpty
                ? env.repository.scopedItems(scope: scope)
                : env.repository.search(parsed.freeTextTokens.joined(separator: " "), scope: scope)
            guard !parsed.operators.isEmpty else { return base }
            let context = auditContext(for: base, operators: parsed.operators)
            let operated = base.filter { SearchOperators.matches($0, operators: parsed.operators, context: context) }
            // Zero-result fallback: same scope, whole query as literal text.
            guard operated.isEmpty else { return operated }
            return env.repository.search(trimmed, scope: scope)
        }
    }

    /// Builds only the signals the recognized operators actually need, computed
    /// once per query over `pool` (already scope-filtered — never the whole
    /// vault). `PasswordAudit.analyze` here is therefore scoped-relative: an
    /// item reused elsewhere in the vault but unique within this scope is not
    /// flagged "reused" — intentional, matches the scope-isolation invariant.
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
        VStack(spacing: 0) {
            // Always visible while searching (Telegram-style), even before typing:
            // the results below list everything in the selected scope until a query
            // narrows them.
            if availableScopes.count > 1 {
                SearchScopeBar(scopes: availableScopes, selection: $scope, title: { label(for: $0) })
            }
            resultsContent
        }
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.groupedBackground))
        // Tapping anywhere drops the keyboard; simultaneous so result rows still tap.
        .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
        .onAppear(perform: seedScope)
    }

    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }

    /// Seed the default scope once. Delegated to the repository so isolation is
    /// fail-closed: a strictAnonymous persona is never seeded to `.allSpaces` (which
    /// would run a global cross-persona search even with the chip hidden).
    private func seedScope() {
        guard !didSeedScope else { return }
        didSeedScope = true
        scope = env.repository.defaultSearchScope(currentSpaceId: currentSpaceId)
    }

    @ViewBuilder private var resultsContent: some View {
        if results.isEmpty {
            emptyInScope
        } else {
            List {
                if trimmed.isEmpty {
                    // Browse mode: smart sections per scope (by type / group / owner).
                    ForEach(browseSections) { section in
                        Section {
                            ForEach(section.items) { VaultItemRowLink(item: $0, highlight: "") }
                        } header: {
                            Text(section.title)
                        }
                    }
                } else {
                    // Search mode: a flat, ranked list.
                    ForEach(results) { VaultItemRowLink(item: $0, highlight: trimmed) }
                }
            }
            .platformInsetGroupedListStyle()
            .textCase(nil)                 // section titles shown as-is, not uppercased
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    // MARK: Browse-mode grouping (no query) — sections depend on the active scope.

    private struct BrowseSection: Identifiable {
        let id: String
        let title: String
        let items: [VaultItem]
    }

    private var browseSections: [BrowseSection] {
        switch scope {
        case .thisSpace:    return groupedByCategory(results)   // by vault type
        case .allSpaces:    return groupedByFolder(results)     // by Space name
        case .sharedWithMe: return groupedByOwner(results)      // by who shared it
        }
    }

    private func sortedByTitle(_ items: [VaultItem]) -> [VaultItem] {
        items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func groupedByCategory(_ items: [VaultItem]) -> [BrowseSection] {
        let grouped = Dictionary(grouping: items, by: \.category)
        return ItemCategory.allCases.compactMap { category in
            guard let group = grouped[category], !group.isEmpty else { return nil }
            return BrowseSection(id: category.rawValue,
                                 title: String(localized: category.title),
                                 items: sortedByTitle(group))
        }
    }

    private func groupedByFolder(_ items: [VaultItem]) -> [BrowseSection] {
        let names = Dictionary(env.repository.folders.map { ($0.id, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: items, by: { $0.folderId })
        var sections: [BrowseSection] = grouped.compactMap { folderId, group in
            guard let folderId else { return nil }
            return BrowseSection(id: folderId,
                                 title: names[folderId] ?? appString("Unfiled"),
                                 items: sortedByTitle(group))
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        // Unfiled last.
        if let unfiled = grouped[nil], !unfiled.isEmpty {
            sections.append(BrowseSection(id: "__unfiled__", title: appString("Unfiled"),
                                          items: sortedByTitle(unfiled)))
        }
        return sections
    }

    private func groupedByOwner(_ items: [VaultItem]) -> [BrowseSection] {
        let grouped = Dictionary(grouping: items) { $0.sharedOrigin?.ownerName ?? appString("Shared with Me") }
        return grouped.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { owner in BrowseSection(id: owner, title: owner, items: sortedByTitle(grouped[owner] ?? [])) }
    }

    /// Empty-in-scope: offer a one-tap widen to All Spaces (when allowed), rather
    /// than a dead end. Falls back to the plain no-results view otherwise.
    @ViewBuilder private var emptyInScope: some View {
        if scope != .allSpaces, env.repository.allSpacesSearchAllowed {
            ContentUnavailableView {
                Label { Text("No results") } icon: { PolarisIcon(Icons.search, size: 48) }
            } description: {
                Text(emptyMessage)
            } actions: {
                Button { scope = .allSpaces } label: { Text("Search all Spaces") }
            }
        } else {
            ContentUnavailableView.search(text: query)
        }
    }

    private var emptyMessage: String {
        let scopeName: String
        switch scope {
        case .thisSpace(let id): scopeName = folderName(id)
        case .sharedWithMe: scopeName = appString("Shared with Me")
        case .allSpaces: scopeName = appString("All Spaces")
        }
        return appString("No results in \(scopeName)")
    }

    private func label(for scope: SpaceScope) -> String {
        switch scope {
        case .thisSpace(let id): return folderName(id)
        case .allSpaces: return appString("All Spaces")
        case .sharedWithMe: return appString("Shared with Me")
        }
    }

    private func folderName(_ id: String) -> String {
        env.repository.activePersonaSpaces.first { $0.id == id }?.name ?? appString("This Space")
    }
}

/// Telegram-style scope filter: a horizontal row of text filters where only the
/// SELECTED one carries a rounded chip — Liquid Glass on iOS 26, a solid capsule
/// otherwise. The active chip animates when the selection changes.
private struct SearchScopeBar: View {
    @Environment(AppEnvironment.self) private var env
    let scopes: [SpaceScope]
    @Binding var selection: SpaceScope
    let title: (SpaceScope) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s1) {
                ForEach(scopes, id: \.self) { scope in
                    chip(scope)
                }
            }
            .padding(Space.s1)
        }
        .modifier(ScopeTroughGlass())          // outer Liquid Glass trough, rounded ends
        .padding(.horizontal, Space.gutter)
        .padding(.vertical, Space.s2)
    }

    private func chip(_ scope: SpaceScope) -> some View {
        let isActive = scope == selection
        return Button {
            withAnimation(.snappy(duration: 0.28)) { selection = scope }
            Haptics.tap()
        } label: {
            Text(title(scope))
                .vaultType(.subhead)
                .themedForeground(isActive ? .primary : .secondary)
                .padding(.horizontal, Space.s3)
                .frame(minHeight: Metric.controlSmall)
                .background {
                    // Only the SELECTED chip carries a fill — a raised solid
                    // capsule on the glass trough (glass-on-glass is avoided).
                    if isActive {
                        Capsule().fill(Color(rgb: env.theme.active.elevatedBackground))
                            .elevation(.level1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The outer filter trough: interactive Liquid Glass on iOS 26 (guarded so a
/// pre-Xcode-26 CI build never sees the symbol), a pressed-surface capsule
/// otherwise. Rounded ends; the chips scroll and clip within it.
private struct ScopeTroughGlass: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = Capsule()
        return Group {
            #if compiler(>=6.2)
            if #available(iOS 26, macOS 26, *), !reduceTransparency {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(Color(rgb: env.theme.active.surfacePressed), in: shape)
            }
            #else
            content.background(Color(rgb: env.theme.active.surfacePressed), in: shape)
            #endif
        }
        .clipShape(shape)
    }
}
