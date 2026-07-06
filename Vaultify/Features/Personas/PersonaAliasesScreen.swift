import SwiftUI

/// Manage the active persona's email aliases. Pre-relay these are reservations
/// only — nothing forwards yet and no `name@domain` address is ever shown (the
/// relay backend doesn't exist). A persona has one stable alias plus any number
/// of per-site aliases bound to individual logins.
struct PersonaAliasesScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingPerSiteEditor = false

    private var persona: Persona? { env.repository.activePersona }

    var body: some View {
        List {
            Section {
                warningBanner
            }
            .listRowBackground(Color.clear)

            if let persona {
                personaAliasSection(persona)
                perSiteSection(persona)
            }
        }
        .navigationTitle(Text("Email aliases"))
        .sheet(isPresented: $showingPerSiteEditor) {
            if let persona { AliasEditorSheet(persona: persona) }
        }
    }

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label { Text("Coming soon — a receive-only private email relay.") }
                icon: { PolarisIcon(Icons.mail) }
                .vaultType(.subhead)
                .themedForeground(.primary)
            Text("Replies from your destination inbox may reveal your real email address.")
                .vaultType(.footnote)
                .themedForeground(.secondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: env.theme.active.accentSoft), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder private func personaAliasSection(_ persona: Persona) -> some View {
        Section("Persona alias") {
            if let alias = env.repository.personaAlias(forPersona: persona.id) {
                aliasRow(alias, subtitle: persona.displayName)
            } else {
                Button {
                    try? env.repository.createPersonaAlias(for: persona)
                } label: {
                    Label { Text("Reserve a private alias") } icon: { PolarisIcon(Icons.addCircle) }
                }
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    @ViewBuilder private func perSiteSection(_ persona: Persona) -> some View {
        let perSite = env.repository.aliases(forPersona: persona.id).filter { $0.tier == .perSite }
        Section("Per-site aliases") {
            ForEach(perSite) { alias in
                aliasRow(alias, subtitle: alias.boundDomain)
            }
            Button { showingPerSiteEditor = true } label: {
                Label { Text("Add per-site alias") } icon: { PolarisIcon(Icons.addCircle) }
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    private func aliasRow(_ alias: EmailAlias, subtitle: String?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                // Bare local-part pre-relay — AliasAddress guarantees no @domain.
                Text(AliasAddress.display(localPart: alias.localPart, status: alias.status, relayDomain: ""))
                    .vaultType(.body).themedForeground(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).vaultType(.caption).themedForeground(.secondary)
                }
            }
            Spacer()
            Text(statusLabel(alias.status)).vaultType(.caption).themedForeground(.secondary)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { try? env.repository.deleteAlias(alias) } label: {
                Label { Text("Delete") } icon: { PolarisIcon(Icons.trash) }
            }
            if alias.status != .disabled {
                Button { try? env.repository.setAliasStatus(alias, to: .disabled) } label: {
                    Label { Text("Disable") } icon: { PolarisIcon(Icons.hide) }
                }
            }
        }
    }

    private func statusLabel(_ status: AliasStatus) -> String {
        switch status {
        case .reserved: return appString("Reserved")
        case .disabled: return appString("Disabled")
        default:        return appString("Draft")
        }
    }
}
