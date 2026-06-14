import SwiftUI

/// The Vault tab landing: a List with dashboard rows on top (Quick Access,
/// Spaces, Tags) followed by all items grouped by category. When a filter is
/// active (Space or Type) the dashboard rows are hidden and only the filtered,
/// sorted items show. Item rows keep the standard swipe actions.
struct HomeDashboard: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var path: NavigationPath
    var filterCategory: ItemCategory?
    var filterSpace: SpaceFilter = .all
    var sort: VaultSort = .updated

    private var isFiltering: Bool { filterCategory != nil || filterSpace != .all }

    private var baseItems: [VaultItem] {
        var list = env.repository.items
        switch filterSpace {
        case .all: break
        case .unfiled: list = list.filter { $0.folderId == nil }
        case .folder(let id): list = list.filter { $0.folderId == id }
        }
        if let filterCategory { list = list.filter { $0.category == filterCategory } }
        return list
    }

    private func items(for category: ItemCategory) -> [VaultItem] {
        sort.apply(baseItems.filter { $0.category == category })
    }
    private var visibleCategories: [ItemCategory] {
        ItemCategory.allCases.filter { !items(for: $0).isEmpty }
    }
    private var hasQuickAccess: Bool {
        env.repository.items.contains(where: \.favorite) || !env.repository.recentlyUsed(limit: 1).isEmpty
    }

    var body: some View {
        List {
            if !isFiltering {
                if hasQuickAccess { dashboardRow { QuickAccessSection(path: $path) } }
                if env.repository.folders.count >= 2 { dashboardRow { SpacesSection(path: $path) } }
                if !env.repository.allTags().isEmpty { dashboardRow { TagsSection(path: $path) } }
            }

            ForEach(visibleCategories) { category in
                Section {
                    ForEach(items(for: category)) { VaultItemRowLink(item: $0) }
                } header: {
                    HStack {
                        Text(category.title)
                        Spacer()
                        Text("\(items(for: category).count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if visibleCategories.isEmpty {
                ContentUnavailableView {
                    Label { Text("No items here") } icon: { PolarisIcon(Icons.search, size: 40) }
                }
            }
        }
    }

    /// A full-bleed, separator-free, transparent List row hosting a dashboard
    /// section (the section draws its own cards over the grouped background).
    private func dashboardRow(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
