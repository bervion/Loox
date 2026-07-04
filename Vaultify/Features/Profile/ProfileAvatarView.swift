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
        let badgeForeground = Color(rgb: env.theme.active.accentForeground)
        let badgeBackground = Color(rgb: env.theme.active.accent)
        return ZStack(alignment: .bottomTrailing) {
            avatar
            PhotosPicker(selection: $picked, matching: .images) {
                PolarisIcon(Icons.camera, size: 15)
                    .foregroundStyle(badgeForeground)
                    .frame(width: 30, height: 30)
                    .background(badgeBackground, in: Circle())
            }
        }
        .onChange(of: picked) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = PlatformImage.fromData(data) {
                    env.repository.setAvatar(image, for: identity.id)
                }
            }
        }
    }

    @ViewBuilder private var avatar: some View {
        if let image = env.repository.avatarImage(for: identity.id) {
            Image(platformImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ItemThumbnail(title: identity.title, category: .identity, iconAsset: nil, size: size)
                .clipShape(Circle())
        }
    }
}
