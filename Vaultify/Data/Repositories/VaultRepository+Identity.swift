import Foundation
import SwiftData

/// Default-identity API on top of `VaultRepository`. The single-active-default invariant
/// is converged in `normalizeDefaultIdentity()` (sibling file, runs inside `reload()`),
/// which can mutate the file-private `items`; this extension only reads `items` and drives
/// record writes via `writeIdentityDefault`.
extension VaultRepository {

    /// Identities the user can act on now — excludes trashed/archived (`items` already does).
    var activeIdentities: [VaultItem] { items.filter { $0.category == .identity } }

    /// The single active default identity, if any. `nil` → UI shows a zero-identity state.
    var defaultIdentity: VaultItem? { activeIdentities.first(where: \.isDefaultIdentity) }

    /// Make `item` the sole default among active identities. No-op unless `item` is itself
    /// an active identity. Bumps `updatedAt` on every identity whose flag changes (required
    /// so the change syncs), then reloads (which re-normalizes to a single default).
    func setDefaultIdentity(_ item: VaultItem) {
        guard item.category == .identity,
              activeIdentities.contains(where: { $0.id == item.id }) else { return }
        let now = Date()
        for identity in activeIdentities where identity.isDefaultIdentity != (identity.id == item.id) {
            writeIdentityDefault(id: identity.id, isDefault: identity.id == item.id, now: now)
        }
        try? store.context.save()
        reload()
    }

    /// True when `item` is the only remaining active identity — removing it would leave
    /// the user with zero identities, which the UI must block.
    func isLastActiveIdentity(_ item: VaultItem) -> Bool {
        item.category == .identity
            && activeIdentities.count == 1
            && activeIdentities.first?.id == item.id
    }

    /// Gate for trash/archive of an identity. `.lastActiveIdentity` → UI blocks with a modal.
    enum IdentityRemovalGate: Equatable { case ok, lastActiveIdentity }

    func identityRemovalGate(_ item: VaultItem) -> IdentityRemovalGate {
        isLastActiveIdentity(item) ? .lastActiveIdentity : .ok
    }
}
