import Foundation

/// Which Spaces a search covers. Chosen per search session and never persisted
/// — the default is seeded from the current Home Space each time search opens.
enum SpaceScope: Equatable, Hashable {
    /// A single specific Space (folder id).
    case thisSpace(id: String)
    /// Every Space. Gated by `VaultRepository.allSpacesSearchAllowed`.
    case allSpaces
    /// The read-only "Shared with Me" projection (not a real Space; no folder id).
    case sharedWithMe
}
