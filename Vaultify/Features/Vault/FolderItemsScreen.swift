import SwiftUI

/// Items in one folder ("Space"), or Unfiled when `folderId == nil`. The screen
/// accent is tinted to the folder's color (scoped to this pushed view, so it
/// doesn't bleed back into Home).
struct FolderItemsScreen: View {
    @Environment(AppEnvironment.self) private var env
    let folderId: String?
    @State private var sort = VaultSort()
    @State private var category: ItemCategory?

    private var folder: Folder? {
        guard let folderId else { return nil }
        return env.repository.folders.first { $0.id == folderId }
    }
    private var items: [VaultItem] {
        var pool = env.repository.items(inFolder: folderId)
        if let category { pool = pool.filter { $0.category == category } }
        return sort.apply(pool)
    }
    private var title: String { folder?.displayName ?? appString("Unfiled") }

    var body: some View {
        List {
            VaultItemSections(items: items, sort: sort)
        }
        .platformInsetGroupedListStyle()
        .themedFormBackground()
        .navigationTitle(title)
        .platformNavigationBarTitleDisplayMode(.inline)
        .tint(folder?.color.tint)
        .toolbar {
            ToolbarItem(placement: .platformPrimaryAction) {
                VaultSortFilterMenu(sort: $sort, category: $category)
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label { Text("No items here") } icon: { VaultIcon(Icons.folder, size: Metric.iconTileLarge) }
                }
            }
        }
    }
}
