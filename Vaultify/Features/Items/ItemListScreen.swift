import SwiftUI

/// A filtered item list for one category (reached from the Items tab). Items are
/// reactive from the repository; sortable; with an empty-state. No category
/// filter here — the category IS the screen.
struct ItemListScreen: View {
    @Environment(AppEnvironment.self) private var env
    let category: ItemCategory
    @State private var sort = VaultSort()

    private var items: [VaultItem] { sort.apply(env.repository.items(ofCategory: category)) }

    var body: some View {
        List {
            VaultItemSections(items: items, sort: sort)
        }
        .platformInsetGroupedListStyle()
        .themedFormBackground()
        .navigationTitle(String(localized: category.title))
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .platformPrimaryAction) {
                VaultSortFilterMenu(sort: $sort)
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label { Text("No items here") } icon: { VaultIcon(category.iconAsset, size: Metric.iconTileLarge) }
                }
            }
        }
    }
}
