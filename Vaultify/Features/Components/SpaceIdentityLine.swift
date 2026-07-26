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

/// The Space and its owning identity in one line: folder badge + name, then a
/// faint "|" divider (owner-requested — an explicit exception to the
/// no-separator copy rule) and the persona's round avatar + display name.
/// Shared by the detail header pill, the editor's Space selector, and the
/// Located In sheet so "whose Space is this" reads the same everywhere.
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
            if let folder {
                FolderBadge(icon: folder.iconAsset, color: folder.color, size: badgeSize)
                Text(folder.name)
                    .vaultType(.subhead).fontWeight(.semibold).themedForeground()
                    .lineLimit(1).truncationMode(.tail)
            } else {
                Text("No Space").vaultType(.subhead).themedForeground(.secondary)
            }
            if let persona {
                Text(verbatim: "|")
                    .vaultType(.subhead)
                    .themedForeground(.tertiary)
                PersonaOwnAvatarView(persona: persona, size: badgeSize)
                Text(verbatim: persona.displayName)
                    .vaultType(.subhead).themedForeground(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
        }
    }
}
