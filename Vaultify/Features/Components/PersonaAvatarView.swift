import SwiftUI

/// Circular avatar for the ACTIVE persona — the stored identity photo when one
/// exists, otherwise the Loox dots mark. Shared by Home's identity card
/// (iPhone) and the iPad/Mac sidebar profile row so the two never drift.
/// Never another persona's photo (an anonymous persona must not wear the
/// personal picture — INV-R03).
struct PersonaAvatarView: View {
    @Environment(AppEnvironment.self) private var env
    var size: CGFloat = 44

    var body: some View {
        if let identity = env.repository.activeProfileItem,
           let image = env.repository.avatarImage(for: identity.id) {
            Image(platformImage: image).resizable().scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            LooxDotsAvatar(size: size)
        }
    }
}

/// Display strings for the active persona, shared by every surface that shows
/// the identity row (Home card, sidebar profile row).
enum PersonaDisplay {
    /// The PERSON's name, not the persona label: the identity card's title
    /// ("Kiyo Chinh") when one is linked — the subtitle already carries the
    /// persona kind, so the bold line can be the human. Falls back to the
    /// persona's display name before an identity card exists.
    static func name(_ env: AppEnvironment) -> String {
        let title = env.repository.activeProfileItem?.title
            .trimmingCharacters(in: .whitespaces)
        if let title, !title.isEmpty { return title }
        return env.repository.activePersona?.displayName ?? appString("Profile")
    }

    /// Kind + email, comma-joined (user-chosen format: "Cá nhân, email…").
    /// Uses the persona-scoped resolver so a strictAnonymous persona never
    /// shows another identity's email (INV-R03).
    static func subtitle(_ env: AppEnvironment) -> String {
        guard let persona = env.repository.activePersona else { return appString("Set up your identity") }
        let kind = PersonaKindStyle.label(persona.kind)
        if let email = env.repository.identityUsername(forPersona: persona), !email.isEmpty {
            return "\(kind), \(email)"
        }
        return kind
    }
}
