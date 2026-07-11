import SwiftUI
import PhotosUI

/// Large circular profile avatar with a PhotosPicker badge to change it. Falls back to the
/// title letter-avatar when no image is stored. Saving downscales + seals via the repository.
struct ProfileAvatarView: View {
    let identity: VaultItem
    var size: CGFloat = 96
    @Environment(AppEnvironment.self) private var env
    @State private var picked: PhotosPickerItem?

    var body: some View {
        // Resolve themed colors on the main actor before the Sendable PhotosPicker label closure.
        let badgeForeground = Color(rgb: env.theme.active.accent)
        let badgeBackground = Color(rgb: env.theme.active.elevatedBackground)
        let badgeRing = Color(rgb: env.theme.active.separator)
        return ZStack(alignment: .bottomTrailing) {
            avatar
            // Camera badge: a quiet surface CIRCLE with an accent glyph (system
            // Contacts convention), tucked ON the avatar corner — the old solid
            // accent square floating off the corner shouted louder than the photo.
            PhotosPicker(selection: $picked, matching: .images) {
                PolarisIcon(Icons.camera, size: 15)
                    .foregroundStyle(badgeForeground)
                    .frame(width: 30, height: 30)
                    .background(badgeBackground, in: Circle())
                    .overlay(Circle().strokeBorder(badgeRing, lineWidth: 0.5))
                    .elevation(.level1)
                    // Hit-test only (no layout/visual change): pads the 30pt chip up to the
                    // 44pt minimum tap target so a thumb doesn't need pixel precision.
                    .contentShape(Rectangle().inset(by: -7))
            }
            .accessibilityLabel(Text("Change photo"))
        }
        .onChange(of: picked) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = PlatformImage.fromData(data) {
                    env.repository.setAvatar(image, for: identity.id)
                    // Avatar is a synced column (sealed) — push the change to iCloud now so it
                    // reaches other devices immediately instead of on the next sync cycle.
                    env.syncNow()
                }
            }
        }
    }

    /// Rounded-square (not circular) avatar — a gentle corner proportional to the size.
    private var avatarShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
    }

    @ViewBuilder private var avatar: some View {
        if let image = env.repository.avatarImage(for: identity.id) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(avatarShape)
        } else {
            ItemThumbnail(title: identity.title, category: .identity, iconAsset: nil, size: size)
                .clipShape(avatarShape)
        }
    }
}
