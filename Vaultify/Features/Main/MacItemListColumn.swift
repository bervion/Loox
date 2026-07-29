#if os(macOS)
import SwiftUI

/// Middle column of the Mac shell: a selectable item list. Selecting a row shows
/// it in the detail column (no push). Reuses the shared `VaultItemRow` content
/// with the core quick actions on a context menu.
struct MacItemListColumn: View {
    @Environment(AppEnvironment.self) private var env
    let items: [VaultItem]
    @Binding var selection: String?

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label { Text("No items") } icon: { VaultIcon(Icons.apps, size: 40) }
                } description: {
                    Text("Items you add will appear here.")
                }
            } else {
                List(selection: $selection) {
                    ForEach(items) { item in
                        VaultItemRow(item: item, showSpace: true)
                            .tag(item.id)
                            .contextMenu {
                                Button { try? env.repository.toggleFavorite(item) } label: {
                                    Label(item.favorite ? "Unfavorite" : "Favorite",
                                          image: item.favorite ? Icons.starFill : Icons.star)
                                }
                                Button(role: .destructive) {
                                    try? env.repository.moveToTrash(item)
                                } label: {
                                    Label { Text("Trash") } icon: { VaultIcon(Icons.trash) }
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color(rgb: env.theme.active.background))
    }
}
#endif
