import SwiftUI

/// The user's identity profile: avatar, default-identity fields with quick-copy, a default
/// switcher across identities, and a payment-cards section. Presented as a sheet from Home.
struct ProfileScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editing: EditorTarget?

    private var identity: VaultItem? { env.repository.defaultIdentity }
    private var identities: [VaultItem] { env.repository.activeIdentities }
    private var cards: [VaultItem] { env.repository.items.filter { $0.category == .card } }

    var body: some View {
        VaultSheetScaffold(title: "Profile") {
            Group {
                if let identity {
                    profile(identity)
                } else {
                    emptyState
                }
            }
        }
        .sheet(item: $editing) { ItemEditorScreen(target: $0) }
    }

    // MARK: Populated profile

    @ViewBuilder private func profile(_ identity: VaultItem) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                ProfileAvatarView(identity: identity)
                    .padding(.top, Space.s4)
                Text(verbatim: identity.title).vaultType(.section).themedForeground()

                if identities.count > 1 { switcher(identity) }
                fieldsCard(identity)
                if !cards.isEmpty { cardsCard }

                Button { editing = .edit(identity) } label: {
                    Text("Edit profile").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                .controlSize(.large)
            }
            .padding(Space.gutter)
        }
    }

    /// Switch which identity is the default (only shown with 2+ identities).
    @ViewBuilder private func switcher(_ current: VaultItem) -> some View {
        Menu {
            ForEach(identities) { id in
                Button { env.repository.setDefaultIdentity(id) } label: {
                    Label {
                        Text(verbatim: id.title)
                    } icon: {
                        if id.id == current.id { PolarisIcon(Icons.checkCircle) }
                    }
                }
            }
        } label: {
            row {
                Text("Default identity").vaultType(.body).themedForeground()
                Spacer()
                Text(verbatim: current.title).vaultType(.body).themedForeground(.secondary)
                PolarisIcon(Icons.chevronDown, size: 14).themedForeground(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Each non-empty field as a tap-to-copy row (protected values stay masked).
    @ViewBuilder private func fieldsCard(_ identity: VaultItem) -> some View {
        let fields = identity.fields.filter { !$0.isEmpty }
        VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                if index > 0 { Divider().background(Color(rgb: env.theme.active.separatorOpaque)) }
                Button {
                    env.clipboard.copy(field.value, label: appLabel(field.label))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: appLabel(field.label)).vaultType(.caption).themedForeground(.secondary)
                            Text(verbatim: field.protected ? "••••••••" : field.value)
                                .vaultType(.body).themedForeground().lineLimit(1)
                        }
                        Spacer()
                        PolarisIcon(Icons.copy, size: 18).themedForeground(.secondary)
                    }
                    .padding(Space.gutter)
                }
                .buttonStyle(.plain)
            }
        }
        .background(VaultColors.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Payment cards in the vault — tap to edit, plus an add affordance.
    @ViewBuilder private var cardsCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Payment cards").vaultType(.sectionLabel).themedForeground(.secondary)
            VStack(spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { Divider().background(Color(rgb: env.theme.active.separatorOpaque)) }
                    Button { editing = .edit(card) } label: {
                        HStack(spacing: Space.s3) {
                            ItemThumbnail(title: card.title, category: .card, iconAsset: card.iconAsset, size: 32)
                            Text(verbatim: card.title).vaultType(.body).themedForeground()
                            Spacer()
                            PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.secondary)
                        }
                        .padding(Space.gutter)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(VaultColors.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: Zero-identity state

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            PolarisIcon(Icons.person, size: 64).foregroundStyle(Color(rgb: env.theme.active.accent))
            Text("No identity yet").vaultType(.section).themedForeground()
            Text("Create your identity to fill your details faster.")
                .vaultType(.body).themedForeground(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, Space.s8)
            Spacer()
            Button { editing = .new(.identity) } label: {
                Text("Create identity").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .padding(Space.gutter)
        }
    }

    @ViewBuilder private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(content: content)
            .padding(Space.gutter)
            .background(VaultColors.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
