import SwiftUI
import PhotosUI

/// Large circular profile avatar. Without a stored photo it shows the Loox dots
/// mark whose spark bubbles into a camera glyph on a loop — the whole mark is
/// the photo picker. With a photo, tapping the avatar offers Change / Remove,
/// and the corner camera badge remains the quick change affordance.
struct ProfileAvatarView: View {
    let identity: VaultItem
    var size: CGFloat = 96
    @Environment(AppEnvironment.self) private var env
    @State private var picked: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showOptions = false

    var body: some View {
        Group {
            if let image = env.repository.avatarImage(for: identity.id) {
                photoAvatar(image)
            } else {
                // No photo yet: the animated dots mark IS the picker button.
                PhotosPicker(selection: $picked, matching: .images) {
                    LooxDotsAvatar(size: size, animatesCamera: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Change photo"))
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $picked, matching: .images)
        .confirmationDialog("Profile photo", isPresented: $showOptions, titleVisibility: .hidden) {
            Button("Change photo") { showPicker = true }
            Button("Remove photo", role: .destructive) {
                env.repository.setAvatar(nil, for: identity.id)
                env.syncNow()
            }
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

    /// Stored photo in a circle; tap for Change / Remove, corner badge for a
    /// one-tap change (system Contacts convention).
    private func photoAvatar(_ image: PlatformImage) -> some View {
        let badgeForeground = Color(rgb: env.theme.active.accent)
        let badgeBackground = Color(rgb: env.theme.active.elevatedBackground)
        let badgeRing = Color(rgb: env.theme.active.separator)
        return ZStack(alignment: .bottomTrailing) {
            Button { showOptions = true } label: {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Profile photo"))

            PhotosPicker(selection: $picked, matching: .images) {
                VaultIcon(Icons.camera, size: 15)
                    .foregroundStyle(badgeForeground)
                    .frame(width: 30, height: 30)
                    .background(badgeBackground, in: Circle())
                    .overlay(Circle().strokeBorder(badgeRing, lineWidth: 0.5))
                    .elevation(.level1)
                    // Hit-test only: pads the 30pt chip up to the 44pt minimum.
                    .contentShape(Rectangle().inset(by: -7))
            }
            .accessibilityLabel(Text("Change photo"))
        }
    }
}
