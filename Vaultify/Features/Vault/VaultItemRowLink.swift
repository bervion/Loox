import SwiftUI

/// A vault item row wrapped in a `NavigationLink` to its detail, with the
/// standard trailing-trash / leading-favorite swipe actions. Shared by Home's
/// filtered lists, the All Items browse, and search results.
struct VaultItemRowLink: View {
    let item: VaultItem
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        NavigationLink(value: item.id) { VaultItemRow(item: item) }
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
    }
}
