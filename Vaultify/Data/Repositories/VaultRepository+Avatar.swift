import UIKit
import SwiftData

/// Identity avatar storage. The avatar is a downscaled JPEG sealed with the Vault Key into
/// the item's `avatarSealed` column, so it syncs cross-device with the record (zero-knowledge)
/// and is removed automatically when the record is deleted (no orphan blobs).
extension VaultRepository {

    /// Decode the stored avatar for an item, or `nil` (→ letter-avatar fallback).
    func avatarImage(for id: String) -> UIImage? {
        guard let key = session.vaultKey,
              let sealed = store.record(id: id)?.avatarSealed,
              let data = try? AESGCM.open(sealed, key: key) else { return nil }
        return UIImage(data: data)
    }

    /// Set (or clear, when `image == nil`) an item's avatar: downscale → JPEG → seal into the
    /// `avatarSealed` column. Bumps `updatedAt` so the change propagates through the
    /// whole-record LWW sync, marks the record dirty, then reloads.
    func setAvatar(_ image: UIImage?, for id: String) {
        guard let key = session.vaultKey, let record = store.record(id: id) else { return }
        if let image {
            // Processing/sealing failure → no-op, so a transient error never silently wipes
            // an existing avatar (nor bumps updatedAt to push that empty state to other devices).
            guard let jpeg = AvatarImage.downscaledJPEG(image),
                  let sealed = try? AESGCM.seal(jpeg, key: key) else { return }
            record.avatarSealed = sealed
        } else {
            record.avatarSealed = nil  // explicit clear
        }
        record.updatedAt = .now
        record.dirty = true
        try? store.context.save()
        reload()
    }
}
