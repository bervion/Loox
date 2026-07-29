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
        .platformInsetGroupedListStyle()
        .themedFormBackground()
        .navigationTitle("#\(tag)")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .platformPrimaryAction) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(VaultSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: { VaultIcon("ic_sort", size: 22) }
                    .accessibilityLabel(Text("Sort"))
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
