import SwiftUI

/// What a caller wants the pushed list to show. Codable so it can ride in
/// `VaultRoute` (navigation paths are state-restored).
struct ItemFilter: Hashable, Codable {
    /// Restrict to one Space; nil = every Space of the active persona.
    var spaceId: String?
    /// Only items that hold a passkey (the hub's Passkey tile).
    var passkeysOnly: Bool
    /// Pre-seeded text for the list's own search field.
    var query: String

    init(spaceId: String? = nil, passkeysOnly: Bool = false, query: String = "") {
        self.spaceId = spaceId
        self.passkeysOnly = passkeysOnly
        self.query = query
    }
}

/// A pushed, titled item list over a filter — the browse counterpart to the
/// keyword-only Search tab (the 1Password split: browse = pushed lists with
/// local search, search = global keyword). Reached via `VaultRoute.filtered`
/// from Home's "See all" and the Loox hub, so filtered views are real pushes
/// with a Back button instead of tab jumps.
struct FilteredItemsScreen: View {
    @Environment(AppEnvironment.self) private var env
    let filter: ItemFilter
    /// Live narrowing — seeded from the spec, adjustable in the toolbar menu.
    @State private var spaceId: String?
    @State private var query: String
    @State private var sort: VaultSort = .updated

    init(filter: ItemFilter) {
        self.filter = filter
        _spaceId = State(initialValue: filter.spaceId)
        _query = State(initialValue: filter.query)
    }

    private var folder: Folder? {
        guard let spaceId else { return nil }
        return env.repository.activePersonaSpaces.first { $0.id == spaceId }
    }

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var items: [VaultItem] {
        var pool = spaceId != nil
            ? env.repository.items(inFolder: spaceId)
            : env.repository.activePersonaItems
        if filter.passkeysOnly {
            let ids = env.repository.passkeyItemIDs(in: pool)
            pool = pool.filter { ids.contains($0.id) }
        }
        if !trimmed.isEmpty {
            // Same contract as the repository's free-text search: every token
            // must match the item's (lowercased) searchable text.
            let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
            pool = pool.filter { item in tokens.allSatisfy { item.searchText.contains($0) } }
        }
        return sort.apply(pool)
    }

    private var title: String {
        if filter.passkeysOnly { return appString("Passkeys") }
        return folder?.name ?? appString("All Items")
    }

    var body: some View {
        List {
            Section {
                ForEach(items) {
                    VaultItemRowLink(item: $0, showSpace: spaceId == nil, highlight: trimmed)
                }
            } header: {
                // The owning identity + Space, same line as the detail header —
                // "whose Space am I browsing" without repeating it on every row.
                if let folder {
                    SpaceIdentityLine(folder: folder)
                        .textCase(nil)
                        .padding(.bottom, Space.s1)
                }
            }
        }
        .platformInsetGroupedListStyle()
        .themedFormBackground()
        .navigationTitle(title)
        .platformNavigationBarTitleDisplayMode(.inline)
        .tint(folder?.color.tint)
        .searchable(text: $query, prompt: "Search")
        .autocorrectionDisabled()
        .platformAutocapitalization(.never)
        .toolbar {
            ToolbarItem(placement: .platformPrimaryAction) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(VaultSort.allCases) { Text($0.label).tag($0) }
                    }
                    if env.repository.activePersonaSpaces.count > 1 || spaceId != nil {
                        // "Spaces", NOT "Space" — that key doubles as the password
                        // generator's separator option ("Dấu cách" in VI).
                        Picker("Spaces", selection: $spaceId) {
                            Text("All Spaces").tag(String?.none)
                            ForEach(env.repository.activePersonaSpaces) { space in
                                Text(verbatim: space.name).tag(String?.some(space.id))
                            }
                        }
                    }
                } label: { PolarisIcon("ic_sort", size: 22) }
                    .accessibilityLabel(Text("Filter"))
            }
        }
        .overlay {
            if items.isEmpty {
                if trimmed.isEmpty {
                    ContentUnavailableView {
                        Label { Text("No items here") } icon: {
                            PolarisIcon(Icons.folder, size: Metric.iconTileLarge)
                        }
                    }
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .analyticsScreen("filtered_items")
    }
}
