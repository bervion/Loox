import SwiftUI

/// Items in one folder ("Space"), or Unfiled when `folderId == nil`. The screen
/// accent is tinted to the folder's color (scoped to this pushed view, so it
/// doesn't bleed back into Home).
struct FolderItemsScreen: View {
    @Environment(AppEnvironment.self) private var env
    let folderId: String?
    @State private var sort: VaultSort = .updated

    private var folder: Folder? {
        guard let folderId else { return nil }
        return env.repository.folders.first { $0.id == folderId }
    }
    private var items: [VaultItem] { sort.apply(env.repository.items(inFolder: folderId)) }
    private var title: String { folder?.name ?? appString("Unfiled") }

    var body: some View {
        List {
            ForEach(items) { VaultItemRowLink(item: $0, showSpace: false) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(folder?.color.tint)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(VaultSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: { PolarisIcon("ic_sort", size: 22) }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label { Text("No items here") } icon: { PolarisIcon(Icons.folder, size: 40) }
                }
            }
        }
    }
}
