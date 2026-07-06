import SwiftUI

/// Search tab — own NavigationStack + `.searchable`. With `Tab(role: .search)`
/// (iOS 18+) this is the native search surface (search field in the tab bar /
/// above the keyboard on iOS 26). Activating the search field on appear means both
/// the tab-bar search and the Home header magnifier drop straight into search.
struct SearchScreen: View {
    @Environment(UIStateStore.self) private var uiState
    @State private var search = ""
    @State private var searchPresented = false

    var body: some View {
        @Bindable var uiState = uiState
        return NavigationStack(path: $uiState.searchPath) {
            SearchResultsList(query: search)
                .navigationTitle("Search")
                .searchable(text: $search, isPresented: $searchPresented, prompt: "Search vault")
                .autocorrectionDisabled()
                .platformAutocapitalization(.never)
                .vaultNavigationDestinations()
        }
        .onAppear { searchPresented = true }
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
              env.repository.folders.contains(where: { $0.id == saved }) else { return nil }
        return saved
    }

    /// Shared-with-Me is offered as a scope only when there is something to show —
    /// mirrors the Items screen's pseudo-space gate.
    private var showsSharedScope: Bool {
        env.settings.approvalModeEnabled || !env.sharedItems.items.isEmpty
    }

    private var availableScopes: [SpaceScope] {
        var out: [SpaceScope] = []
        if let id = currentSpaceId { out.append(.thisSpace(id: id)) }
        if env.repository.allSpacesSearchAllowed { out.append(.allSpaces) }
        if showsSharedScope { out.append(.sharedWithMe) }
        return out
    }

    private var results: [VaultItem] {
        switch scope {
        case .sharedWithMe:
            let tokens = trimmed.lowercased().split(separator: " ")
            guard !tokens.isEmpty else { return [] }
            return env.sharedItems.items.filter { item in
                tokens.allSatisfy { item.searchText.contains($0) }
            }
        case .thisSpace, .allSpaces:
            return env.repository.search(trimmed, scope: scope)
        }
    }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                ContentUnavailableView {
                    Label { Text("Search your vault") } icon: { PolarisIcon(Icons.search, size: 48) }
                } description: {
                    Text("Find items by name, site, tag, or Space.")
                }
            } else {
                VStack(spacing: 0) {
                    scopeChips
                    resultsContent
                }
            }
        }
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.groupedBackground))
        .onAppear(perform: seedScope)
    }

    /// Seed the default scope once: the current Home Space if set, else All Spaces.
    private func seedScope() {
        guard !didSeedScope else { return }
        didSeedScope = true
        scope = currentSpaceId.map { .thisSpace(id: $0) } ?? .allSpaces
    }

    @ViewBuilder private var scopeChips: some View {
        let chips = availableScopes
        if chips.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    ForEach(chips, id: \.self) { chipScope in
                        ScopeChip(label: label(for: chipScope), isActive: scope == chipScope) {
                            scope = chipScope
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                .padding(.vertical, Space.s2)
            }
        }
    }

    @ViewBuilder private var resultsContent: some View {
        if results.isEmpty {
            emptyInScope
        } else {
            List(results) { VaultItemRowLink(item: $0) }
                .platformInsetGroupedListStyle()
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
        }
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
        env.repository.folders.first { $0.id == id }?.name ?? appString("This Space")
    }
}

/// A single search-scope pill. Active = accent-soft fill; inactive = pressed surface.
private struct ScopeChip: View {
    @Environment(AppEnvironment.self) private var env
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .vaultType(.footnote)
                .themedForeground(isActive ? .accent : .secondary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .background(
                    Color(rgb: isActive ? env.theme.active.accentSoft : env.theme.active.surfacePressed),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}
