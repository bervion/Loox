import SwiftUI

/// Push destinations shared by the Home / Items / Search NavigationStacks. Item
/// detail is keyed separately by the item id (`String`).
enum VaultRoute: Hashable, Codable {
    case folder(String?)            // nil = Unfiled
    case tag(String)
    case category(ItemCategory)
    case manageFolders
    case archive
    case recentlyDeleted
}

/// Sort order shared by the item browse lists.
enum VaultSort: String, CaseIterable, Identifiable {
    case updated, title
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .updated ? "Recently Updated" : "Title" }

    func apply(_ items: [VaultItem]) -> [VaultItem] {
        switch self {
        case .updated: items.sorted { $0.updatedAt > $1.updatedAt }
        case .title: items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}

extension View {
    /// The destinations every tab stack can push. Declared once (DRY) so Home,
    /// Items, and Search resolve item detail + folder/tag/category/archive/trash.
    func vaultNavigationDestinations() -> some View {
        self
            .navigationDestination(for: String.self) { id in
                // Deferred zoom (Design DNA #5): no-op unless the enclosing stack injected
                // `\.vaultZoomNamespace` (currently Search) — every other caller of this
                // shared modifier gets the ordinary push, unaffected.
                ItemDetailScreen(itemID: id)
                    .modifier(ZoomTransitionDestination(id: id))
                    .fullScreenPush()
            }
            .navigationDestination(for: VaultRoute.self) { route in
                Group {
                    switch route {
                    case .folder(let id): FolderItemsScreen(folderId: id)
                    case .tag(let tag): TagItemsScreen(tag: tag)
                    case .category(let category): ItemListScreen(category: category)
                    case .manageFolders: ManageFoldersScreen()
                    case .archive: ArchiveScreen()
                    case .recentlyDeleted: TrashScreen()
                    }
                }
                .fullScreenPush()
            }
            // Shared-with-Me is reachable from Home AND the Items Spaces list.
            // Registered at the stack root — a destination declared inside
            // another destination's content doesn't reliably register,
            // leaving row taps dead.
            .navigationDestination(for: SharedWithMeRoute.self) { _ in SharedWithMeScreen().fullScreenPush() }
            .navigationDestination(for: NotificationsRoute.self) { _ in NotificationsScreen().fullScreenPush() }
    }
}
