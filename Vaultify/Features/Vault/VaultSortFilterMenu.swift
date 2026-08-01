import SwiftUI

/// The sort half of the browse menu: key picker plus a direction picker whose
/// option names adapt to the key. Shared by the list toolbars and Search's
/// chip-row menu so every surface speaks the same sort vocabulary.
struct VaultSortPickers: View {
    @Binding var sort: VaultSort

    var body: some View {
        Picker("Sort", selection: $sort.key) {
            ForEach(VaultSort.Key.allCases) { Text($0.label).tag($0) }
        }
        if sort.key.supportsDirection {
            Picker("Order", selection: $sort.reversed) {
                if sort.key == .title {
                    Text("A to Z").tag(false)
                    Text("Z to A").tag(true)
                } else {
                    Text("Newest First").tag(false)
                    Text("Oldest First").tag(true)
                }
            }
        }
    }
}

/// The browse lists' shared trailing-toolbar menu: sort pickers, an optional
/// category filter, and screen-specific extra pickers (e.g. the Spaces scope).
struct VaultSortFilterMenu<Extra: View>: View {
    @Binding var sort: VaultSort
    var category: Binding<ItemCategory?>?
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        Menu {
            VaultSortPickers(sort: $sort)
            if let category {
                Picker("Categories", selection: category) {
                    Text("All Categories").tag(ItemCategory?.none)
                    ForEach(ItemCategory.allCases) { cat in
                        Label { Text(cat.title) } icon: { VaultIcon(cat.iconAsset) }
                            .tag(ItemCategory?.some(cat))
                    }
                }
            }
            extra()
        } label: { VaultIcon(Icons.sort, size: 22) }
            .accessibilityLabel(Text(category == nil ? "Sort" : "Filter"))
            // One selection haptic per change, fired on the Menu itself: menu
            // CONTENT unmounts as the menu closes, so an `onChange` in there can
            // miss the very change that closed it.
            .onChange(of: sort) { Haptics.tap() }
            .onChange(of: category?.wrappedValue) { Haptics.tap() }
    }
}

extension VaultSortFilterMenu where Extra == EmptyView {
    init(sort: Binding<VaultSort>, category: Binding<ItemCategory?>? = nil) {
        self.init(sort: sort, category: category, extra: { EmptyView() })
    }
}
