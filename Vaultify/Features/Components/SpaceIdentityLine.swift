import SwiftUI

/// Avatar for a SPECIFIC persona — its own photo or the dots mark. Distinct
/// from `PersonaAvatarView` (which always renders the ACTIVE persona):
/// surfaces that show an item's OWNING identity use this, so the picture is
/// always that identity's own (INV-R03 stays intact — nobody borrows a photo).
struct PersonaOwnAvatarView: View {
    let persona: Persona
    var size: CGFloat = 20
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        if let profile = env.repository.profileItem(for: persona),
           let image = env.repository.avatarImage(for: profile.id) {
            Image(platformImage: image).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            LooxDotsAvatar(size: size)
        }
    }
}

/// The owning identity and the Space in one line — round avatar + persona
/// name, a hairline divider, then folder badge + name. Shared by the detail
/// header pill, the editor's Space selector, and the Located In sheet so
/// "whose Space is this" reads the same everywhere.
struct SpaceIdentityLine: View {
    let folder: Folder?
    var badgeSize: CGFloat = 20
    @Environment(AppEnvironment.self) private var env

    private var persona: Persona? {
        guard let personaId = folder?.personaId else { return nil }
        return env.repository.personas.first { $0.id == personaId }
    }

    var body: some View {
        HStack(spacing: Space.s2) {
            if let persona {
                PersonaOwnAvatarView(persona: persona, size: badgeSize)
                Text(verbatim: persona.displayName)
                    .vaultType(.subhead).fontWeight(.semibold).themedForeground()
                    .lineLimit(1).truncationMode(.tail)
                // A DRAWN hairline, not the "|" glyph — the character sits on
                // the text baseline and reads misaligned next to badges.
                Capsule()
                    .fill(Color(rgb: env.theme.active.separatorOpaque))
                    .frame(width: 1, height: badgeSize * 0.65)
            }
            if let folder {
                FolderBadge(icon: folder.iconAsset, color: folder.color, size: badgeSize)
                Text(verbatim: folder.displayName)
                    .vaultType(.subhead).fontWeight(.semibold).themedForeground()
                    .lineLimit(1).truncationMode(.tail)
            } else {
                Text("No Space").vaultType(.subhead).themedForeground(.secondary)
            }
        }
    }
}
