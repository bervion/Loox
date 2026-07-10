import SwiftUI

/// A filtered item list for one category (reached from the Items tab). Items are
/// reactive from the repository; sortable; with an empty-state.
struct ItemListScreen: View {
    @Environment(AppEnvironment.self) private var env
    let category: ItemCategory
    @State private var sort: VaultSort = .updated

    private var items: [VaultItem] { sort.apply(env.repository.items(ofCategory: category)) }

    var body: some View {
        List {
            ForEach(items) { VaultItemRowLink(item: $0) }
        }
        .platformInsetGroupedListStyle()
        .themedFormBackground()
        .navigationTitle(String(localized: category.title))
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .platformPrimaryAction) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(VaultSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: { PolarisIcon("ic_sort", size: 22) }
                    .accessibilityLabel(Text("Sort"))
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label { Text("No items here") } icon: { PolarisIcon(category.iconAsset, size: Metric.iconTileLarge) }
                }
            }
        }
    }
}
