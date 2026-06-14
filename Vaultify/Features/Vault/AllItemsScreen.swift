import SwiftUI

/// All items grouped by category (the classic 1Password-style browse), reached
/// from the Home "All Items" card. Sort toggles recently-updated / title.
struct AllItemsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var sort: VaultSort = .updated

    private func items(for category: ItemCategory) -> [VaultItem] {
        sort.apply(env.repository.items.filter { $0.category == category })
    }
    private var visibleCategories: [ItemCategory] {
        ItemCategory.allCases.filter { !items(for: $0).isEmpty }
    }

    var body: some View {
        List {
            ForEach(visibleCategories) { category in
                let categoryItems = items(for: category)
                Section {
                    ForEach(categoryItems) { VaultItemRowLink(item: $0) }
                } header: {
                    HStack {
                        Text(category.title)
                        Spacer()
                        Text("\(categoryItems.count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("All Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { sortMenu } }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) {
                ForEach(VaultSort.allCases) { Text($0.label).tag($0) }
            }
        } label: { PolarisIcon("ic_sort", size: 22) }
    }
}
