import SwiftUI

/// Search tab — own NavigationStack + `.searchable`, so the search bar sits at
/// the top of the screen. Renders `SearchResultsList`.
struct SearchScreen: View {
    @State private var search = ""

    var body: some View {
        NavigationStack {
            SearchResultsList(query: search)
                .navigationTitle("Search")
                .searchable(text: $search, prompt: "Search vault")
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .vaultNavigationDestinations()
        }
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
            }
        }
    }
}
