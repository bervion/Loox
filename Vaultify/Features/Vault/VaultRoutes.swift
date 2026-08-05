import SwiftUI

/// Push destinations shared by the Home / Items / Search NavigationStacks. Item
/// detail is keyed separately by the item id (`String`).
enum VaultRoute: Hashable, Codable {
    case folder(String?)            // nil = Unfiled
    case tag(String)
    case category(ItemCategory)
    case filtered(ItemFilter)       // pushed browse list (space / passkey / keyword)
    case totpCodes                  // full 2FA codes list (rows + search)
    case manageFolders
    case archive
    case recentlyDeleted
}

/// The screen a `VaultRoute` resolves to. Shared by `vaultNavigationDestinations`
/// (SwiftUI-path navigation on the iPad/Mac sidebar) and `AppNavigator` (the
/// compact-iOS UIKit push), so both routes render an identical destination.
@ViewBuilder
func vaultRouteDestination(_ route: VaultRoute) -> some View {
    switch route {
    case .folder(let id): FolderItemsScreen(folderId: id)
    case .tag(let tag): TagItemsScreen(tag: tag)
    case .category(let category): ItemListScreen(category: category)
    case .filtered(let filter): FilteredItemsScreen(filter: filter)
    case .totpCodes: TotpListScreen()
    case .manageFolders: ManageFoldersScreen()
    case .archive: ArchiveScreen()
    case .recentlyDeleted: TrashScreen()
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
                    // Pushed INSIDE a stack (from a folder/tag/category/search
                    // list) — here SwiftUI `dismiss()` pops correctly, so clear the
                    // navigator-root flag inherited from the enclosing push.
                    .environment(\.isNavigatorRoot, false)
                    .modifier(ZoomTransitionDestination(id: id))
                    .fullScreenPush()
            }
            .navigationDestination(for: VaultRoute.self) { route in
                vaultRouteDestination(route).fullScreenPush()
            }
            // Shared-with-Me is reachable from Home AND the Items Spaces list.
            // Registered at the stack root — a destination declared inside
            // another destination's content doesn't reliably register,
            // leaving row taps dead.
            .navigationDestination(for: SharedWithMeRoute.self) { _ in SharedWithMeScreen().fullScreenPush() }
            .navigationDestination(for: NotificationsRoute.self) { _ in NotificationsScreen().fullScreenPush() }
    }
}
