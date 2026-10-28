import SwiftUI

/// Personal Information — the active persona's profile identity (Full Name, Email, Phone,
/// Address, Date of Birth, ID Number) as tap-to-copy rows, with Edit and a picker to switch
/// WHICH identity item fills this profile (`setProfileItem`, not a persona switch). The pool
/// is scoped to the active persona's identities (INV-R03). Reuses `ProfileSectionCard`.
struct PersonalInformationScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editing: EditorTarget?

    private var identity: VaultItem? { env.repository.activeProfileItem }

    private var identities: [VaultItem] {
        guard let persona = env.repository.activePersona else { return env.repository.activeIdentities }
        return env.repository.items(for: persona).filter { $0.category == .identity }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Space.s6) {
                ProfileSectionCard(
                    title: "Identity",
                    emptyTitle: "No identity yet",
                    chooseLabel: identity == nil ? "Choose identity" : "Change identity",
                    // Swap glyph, not a person: the row switches WHICH identity fills this card.
                    icon: Icons.orderRepeat,
                    selected: identity,
                    pool: identities,
                    onEdit: { if let identity { editing = .edit(identity) } },
                    onChoose: { item in
                        // Re-point the ACTIVE persona's profile card (for the default persona
                        // this also moves the synced default-identity marker).
                        if let persona = env.repository.activePersona {
                            env.repository.setProfileItem(item, for: persona)
                        } else {
                            env.repository.setDefaultIdentity(item)
                        }
                    },
                    onCreate: { editing = .new(.identity) })
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Personal Information")
        .platformNavigationBarTitleDisplayMode(.inline)
        .platformEditorCover(item: $editing) { ItemEditorScreen(target: $0) }
    }
}
