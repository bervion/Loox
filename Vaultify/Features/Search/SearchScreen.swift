import SwiftUI

/// Search tab: smart search across all items — every space-separated token must
/// match the item's title/fields/tags OR its Space name (e.g. "github work"
/// finds the GitHub login in the Work space). Taps open detail.
struct SearchScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var search = ""
    @State private var path = NavigationPath()

    private var query: String { search.trimmingCharacters(in: .whitespaces) }
    private var results: [VaultItem] { env.repository.search(query) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if query.isEmpty {
                    ContentUnavailableView {
                        Label { Text("Search your vault") } icon: { PolarisIcon(Icons.search, size: 48) }
                    } description: {
                        Text("Find items by name, site, tag, or Space.")
                    }
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    List(results) { VaultItemRowLink(item: $0) }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $search, prompt: "Search vault")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .vaultNavigationDestinations()
        }
    }
}
