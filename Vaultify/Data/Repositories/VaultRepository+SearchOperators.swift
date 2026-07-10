import Foundation

/// Repository-side support for the Search screen's local operator grammar
/// (`SearchOperators.swift`) — NO AI, NO network, everything below runs over
/// items already decrypted in memory.
extension VaultRepository {

    /// Every item visible under `scope`, with no text/operator filtering applied —
    /// exactly the same partition `search(_:scope:)` uses before it tokenizes the
    /// query. Lets the Search screen run an operator-only query (e.g. "weak", no
    /// free text) without tripping `search`'s "empty query → []" guard.
    ///
    /// Mirrors `search(_:scope:)`'s scoping 1:1 so operator filtering can never
    /// widen beyond what a text search under the same scope would ever surface
    /// (fail-closed persona/Space partition, INV-R03 preserved).
    func scopedItems(scope: SpaceScope) -> [VaultItem] {
        let pool = activePersonaItems
        switch scope {
        case .sharedWithMe:
            // Shared projections aren't vault items; the Search surface supplies
            // them separately for this scope (see `SearchResultsList`).
            return []
        case .thisSpace(let id):
            return pool.filter { $0.folderId == id }
        case .allSpaces:
            return pool
        }
    }

    /// Item ids (within `pool`) that currently have at least one matching
    /// passkey. `pool` MUST already be scope-filtered — this only classifies
    /// membership, never widens the candidate set (the boolean check reads
    /// `passkeys`, a store-wide list, purely to test relying-party match against
    /// items already in `pool`).
    func passkeyItemIDs(in pool: [VaultItem]) -> Set<String> {
        Set(pool.compactMap { item in
            guard item.category == .login, item.autofillHost != nil,
                  passkeys.contains(where: { item.matchesRelyingParty($0.relyingParty) })
            else { return nil }
            return item.id
        })
    }
}
