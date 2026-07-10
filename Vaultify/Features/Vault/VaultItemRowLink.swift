import SwiftUI

/// A vault item row wrapped in a `NavigationLink` to its detail, with the
/// standard trailing-trash / leading-favorite swipe actions. Shared by Home's
/// filtered lists, the All Items browse, and search results. `showSpace` is
/// passed through to `VaultItemRow` (off inside a single-Space view).
struct VaultItemRowLink: View {
    let item: VaultItem
    var showSpace = true
    /// Search query forwarded to `VaultItemRow` for match highlighting.
    var highlight: String? = nil
    @Environment(AppEnvironment.self) private var env
    @State private var showLastIdentityBlock = false

    /// Removing the user's only identity is blocked (the app keeps ≥1 active identity).
    private var isLastIdentity: Bool {
        env.repository.identityRemovalGate(item) == .lastActiveIdentity
    }

    /// Shared projections are read-only guests: no trash/favorite/pin/archive
    /// — a repository mutation with a projected item would UPSERT someone
    /// else's data into the local vault store (review C1).
    private var isSharedProjection: Bool { item.sharedOrigin != nil }

    var body: some View {
        NavigationLink(value: item.id) { VaultItemRow(item: item, showSpace: showSpace, highlight: highlight) }
            .swipeActions(edge: .trailing) {
                if !isSharedProjection {
                    Button(role: .destructive) {
                        if isLastIdentity { showLastIdentityBlock = true } else { try? env.repository.moveToTrash(item) }
                    } label: {
                        Label("Trash", image: Icons.trash)
                    }
                }
            }
            .swipeActions(edge: .leading) {
                if !isSharedProjection {
                    Button {
                        try? env.repository.toggleFavorite(item)
                        Haptics.tap()
                    } label: {
                        Label("Favorite", image: item.favorite ? Icons.starFill : Icons.star)
                    }
                    .tint(VaultColors.strengthMedium)
                }
            }
            .contextMenu {
                if !isSharedProjection {
                    Button {
                        env.repository.togglePin(item)
                        Haptics.tap()
                    } label: {
                        Label(item.pinned ? "Unpin" : "Pin", image: item.pinned ? Icons.pinFill : Icons.pin)
                    }
                    Button {
                        if isLastIdentity { showLastIdentityBlock = true } else { env.repository.archive(item) }
                    } label: {
                        Label("Archive", image: Icons.archive)
                    }
                }
            }
            .listRowBackground(VaultColors.surface)
            .alert("Keep at least one identity", isPresented: $showLastIdentityBlock) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This is your only identity. Add another before removing this one.")
            }
    }
}
