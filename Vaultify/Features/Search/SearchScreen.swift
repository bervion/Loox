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
                .textInputAutocapitalization(.never)
                .vaultNavigationDestinations()
        }
        .onAppear { searchPresented = true }
    }
}

/// Smart-search results — every space-separated token must match the item's
/// title/fields/tags OR its Space name (e.g. "github work"). Taps open detail.
struct SearchResultsList: View {
    @Environment(AppEnvironment.self) private var env
    let query: String

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }
    private var results: [VaultItem] { env.repository.search(trimmed) }

    var body: some View {
        Group {
            if trimmed.isEmpty {
                ContentUnavailableView {
                    Label { Text("Search your vault") } icon: { PolarisIcon(Icons.search, size: 48) }
                } description: {
                    Text("Find items by name, site, tag, or Space.")
                }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { VaultItemRowLink(item: $0) }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
            }
        }
        .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.groupedBackground))
    }
}
