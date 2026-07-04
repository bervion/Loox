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

    private var identity: VaultItem? { env.repository.defaultIdentity }
    private var identities: [VaultItem] { env.repository.activeIdentities }
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

    private var identitySection: some View {
        ProfileSectionCard(
            title: "Identity",
            emptyTitle: "No identity yet",
            chooseLabel: identity == nil ? "Choose identity" : "Change identity",
            icon: Icons.person,
            selected: identity,
            pool: identities,
            onEdit: { if let identity { editing = .edit(identity) } },
            onChoose: { env.repository.setDefaultIdentity($0) },
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
