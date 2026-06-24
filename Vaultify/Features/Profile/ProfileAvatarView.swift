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
        ZStack(alignment: .bottomTrailing) {
            avatar
            PhotosPicker(selection: $picked, matching: .images) {
                PolarisIcon(Icons.camera, size: 15)
                    .foregroundStyle(Color(rgb: env.theme.active.accentForeground))
                    .frame(width: 30, height: 30)
                    .background(Color(rgb: env.theme.active.accent), in: Circle())
            }
        }
        .onChange(of: picked) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    env.repository.setAvatar(image, for: identity.id)
                }
            }
        }
    }

    @ViewBuilder private var avatar: some View {
        if let image = env.repository.avatarImage(for: identity.id) {
            Image(uiImage: image)
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
