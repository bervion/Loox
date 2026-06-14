import SwiftUI

/// Items carrying a given tag (neutral styling — tags have no color).
struct TagItemsScreen: View {
    @Environment(AppEnvironment.self) private var env
    let tag: String
    @State private var sort: VaultSort = .updated

    private var items: [VaultItem] { sort.apply(env.repository.items(withTag: tag)) }

    var body: some View {
        List {
            ForEach(items) { VaultItemRowLink(item: $0) }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
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
                    Label { Text("No items here") } icon: { PolarisIcon(Icons.hashtag, size: 40) }
                }
            }
        }
    }
}
