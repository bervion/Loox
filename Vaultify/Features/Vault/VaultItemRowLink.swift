import SwiftUI

/// A vault item row wrapped in a `NavigationLink` to its detail, with the
/// standard trailing-trash / leading-favorite swipe actions. Shared by Home's
/// filtered lists, the All Items browse, and search results. `showSpace` is
/// passed through to `VaultItemRow` (off inside a single-Space view).
struct VaultItemRowLink: View {
    let item: VaultItem
    var showSpace = true
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        NavigationLink(value: item.id) { VaultItemRow(item: item, showSpace: showSpace) }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { try? env.repository.moveToTrash(item) } label: {
                    Label("Trash", image: Icons.trash)
                }
            }
            .swipeActions(edge: .leading) {
                Button { try? env.repository.toggleFavorite(item) } label: {
                    Label("Favorite", image: item.favorite ? Icons.starFill : Icons.star)
                }
                .tint(VaultColors.strengthMedium)
            }
            .contextMenu {
                Button { env.repository.togglePin(item) } label: {
                    Label(item.pinned ? "Unpin" : "Pin", image: item.pinned ? Icons.pinFill : Icons.pin)
                }
                Button { env.repository.archive(item) } label: {
                    Label("Archive", image: Icons.archive)
                }
            }
            .listRowBackground(VaultColors.surface)
    }
}
