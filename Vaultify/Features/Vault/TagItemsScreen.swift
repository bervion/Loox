import SwiftUI

/// Items carrying a given tag (neutral styling — tags have no color).
struct TagItemsScreen: View {
    @Environment(AppEnvironment.self) private var env
    let tag: String
    @State private var sort = VaultSort()
    @State private var category: ItemCategory?

    private var items: [VaultItem] {
        var pool = env.repository.items(withTag: tag)
        if let category { pool = pool.filter { $0.category == category } }
        return sort.apply(pool)
    }

    var body: some View {
        List {
            VaultItemSections(items: items, sort: sort)
        }
        .platformInsetGroupedListStyle()
        .themedFormBackground()
        .navigationTitle("#\(tag)")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .platformPrimaryAction) {
                VaultSortFilterMenu(sort: $sort, category: $category)
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label { Text("No items here") } icon: { VaultIcon(Icons.hashtag, size: Metric.iconTileLarge) }
                }
            }
        }
    }
}
