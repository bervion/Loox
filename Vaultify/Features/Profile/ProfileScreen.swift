import SwiftUI

/// Navigation route that pushes the Profile screen (kept distinct from the `String`
/// item-detail route). Codable so it survives `homePath` state restoration.
struct ProfileRoute: Hashable, Codable {}

/// The user's profile as two vault-backed sections: their Identity and their Payment card.
/// Each shows the selected item's tap-to-copy fields (or an empty state), an Edit button that
/// opens the item editor, and a picker row to choose which vault item of that type to show.
/// Pushed onto the Home stack (not a sheet); all data mirrors the vault, so there is no
/// separate "edit profile" — editing happens on the underlying items.
struct ProfileScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editing: EditorTarget?

    /// Profile follows the ACTIVE persona: its own profile card, and a picker pool
    /// limited to identities that persona owns (never another persona's — INV-R03).
    private var identity: VaultItem? { env.repository.activeProfileItem }
    private var identities: [VaultItem] {
        guard let persona = env.repository.activePersona else { return env.repository.activeIdentities }
        return env.repository.items(for: persona).filter { $0.category == .identity }
    }
    private var cards: [VaultItem] { env.repository.items.filter { $0.category == .card } }

    /// The card shown in the Payment section: the device-local pick, else the first card.
    private var selectedCard: VaultItem? {
        if let id = env.settings.selectedPaymentCardId, let card = cards.first(where: { $0.id == id }) {
            return card
        }
        return cards.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let identity { avatarHeader(identity) }
                personaSection
                identitySection
                paymentSection
            }
            .padding(Space.gutter)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        .navigationTitle("Profile")
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { ItemEditorScreen(target: $0) }
    }

    /// Avatar header — the tap-badge lets the user change the photo. No name here: the
    /// Identity section below already shows it (and the rest of the vault fields).
    @ViewBuilder private func avatarHeader(_ identity: VaultItem) -> some View {
        ProfileAvatarView(identity: identity)
            .frame(maxWidth: .infinity)
            .padding(.top, Space.s2)
    }

    /// The active persona — the identity you're currently acting as. Shows kind +
    /// isolation, lets you switch, and is the home for persona + email management
    /// (moved here from Settings so identities live with the profile).
    @ViewBuilder private var personaSection: some View {
        if let persona = env.repository.activePersona {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(spacing: Space.s3) {
                    PolarisIcon(PersonaKindStyle.icon(persona.kind), size: Metric.iconUtility)
                        .themedForeground(.accent)
                        .frame(width: 44, height: 44)
                        .background(Color(rgb: env.theme.active.accentSoft),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: persona.displayName).vaultType(.headline).themedForeground()
                        Text(verbatim: personaMeta(persona)).vaultType(.footnote).themedForeground(.secondary)
                    }
                    Spacer()
                    if env.repository.personas.count > 1 {
                        Menu {
                            ForEach(env.repository.personas) { candidate in
                                Button { env.repository.setActivePersona(candidate.id) } label: {
                                    if candidate.id == persona.id {
                                        Label { Text(verbatim: candidate.displayName) } icon: { PolarisIcon(Icons.checkCircle) }
                                    } else {
                                        Text(verbatim: candidate.displayName)
                                    }
                                }
                            }
                        } label: {
                            Text("Switch").vaultType(.subhead).themedForeground(.accent)
                        }
                    }
                }
                Divider().overlay(Color(rgb: env.theme.active.separator))
                NavigationLink { PersonaSwitcherScreen() } label: {
                    personaRowLabel("Manage personas", icon: Icons.person)
                }
                NavigationLink { PersonaAliasesScreen() } label: {
                    personaRowLabel("Email aliases", icon: Icons.mail)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: env.theme.active.elevatedBackground))
            .vaultCornerRadius(Radius.lg)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5))
        }
    }

    private func personaMeta(_ persona: Persona) -> String {
        var parts = [PersonaKindStyle.label(persona.kind)]
        if persona.isolationPolicy != .standard {
            parts.append(PersonaKindStyle.policyLabel(persona.isolationPolicy))
        }
        return parts.joined(separator: " · ")
    }

    private func personaRowLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(icon, size: 18).themedForeground(.iconSecondary)
            Text(title).vaultType(.body).themedForeground()
            Spacer()
            PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
        }
        .contentShape(.rect)
    }

    private var identitySection: some View {
        ProfileSectionCard(
            title: "Identity",
            emptyTitle: "No identity yet",
            chooseLabel: identity == nil ? "Choose identity" : "Change identity",
            icon: Icons.person,
            selected: identity,
            pool: identities,
            onEdit: { if let identity { editing = .edit(identity) } },
            onChoose: { item in
                // Re-point the ACTIVE persona's profile card (for the default
                // persona this also moves the synced default-identity marker).
                if let persona = env.repository.activePersona {
                    env.repository.setProfileItem(item, for: persona)
                } else {
                    env.repository.setDefaultIdentity(item)
                }
            },
            onCreate: { editing = .new(.identity) })
    }

    private var paymentSection: some View {
        ProfileSectionCard(
            title: "Payment",
            emptyTitle: "No payment card yet",
            chooseLabel: selectedCard == nil ? "Choose a card" : "Change card",
            icon: Icons.creditCard,
            selected: selectedCard,
            pool: cards,
            onEdit: { if let selectedCard { editing = .edit(selectedCard) } },
            onChoose: { env.settings.selectedPaymentCardId = $0.id },
            onCreate: { editing = .new(.card) })
    }
}
