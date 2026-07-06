import SwiftUI

/// Manage the active persona's email aliases against the LIVE receive-only
/// relay. A persona has one stable alias plus any number of per-site aliases.
/// Creating an alias reserves it locally then activates it on the relay; an
/// activation that fails (offline, no iCloud) leaves it reserved with a
/// tap-to-activate affordance — local state never lies about what's live.
struct PersonaAliasesScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingPerSiteEditor = false
    @State private var busyAliasID: String?
    @State private var errorMessage: String?

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
            if let persona { AliasEditorSheet(persona: persona, onCreated: { activate($0) }) }
        }
        .alert(Text("Couldn’t reach the relay"), isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Label { Text("Mail sent to an active alias forwards to your inbox. Receive-only.") }
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
                    if let id = try? env.repository.createPersonaAlias(for: persona),
                       let created = env.repository.aliases.first(where: { $0.id == id }) {
                        activate(created)
                    }
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
        // Full working address only when live+active — AliasAddress guarantees it.
        let address = AliasAddress.display(localPart: alias.localPart, status: alias.status,
                                           relayDomain: RelayConfig.emailDomain)
        return Button {
            switch alias.status {
            case .active:
                // Copy the working address (not a secret — no auto-clear urgency).
                env.clipboard.copy(address, label: appString("Email aliases"), sensitive: false)
            case .reserved:
                activate(alias)
            default:
                break
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: address).vaultType(.body).themedForeground(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle).vaultType(.caption).themedForeground(.secondary)
                    }
                }
                Spacer()
                if busyAliasID == alias.id {
                    ProgressView()
                } else {
                    Text(verbatim: statusLabel(alias.status)).vaultType(.caption)
                        .themedForeground(alias.status == .active ? .accent : .secondary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { remove(alias) } label: {
                Label { Text("Delete") } icon: { PolarisIcon(Icons.trash) }
            }
            if alias.status != .disabled {
                Button { disableAlias(alias) } label: {
                    Label { Text("Disable") } icon: { PolarisIcon(Icons.hide) }
                }
            }
        }
    }

    private func statusLabel(_ status: AliasStatus) -> String {
        switch status {
        case .active:   return appString("Active")
        case .reserved: return appString("Tap to activate")
        case .disabled: return appString("Disabled")
        default:        return appString("Draft")
        }
    }

    // MARK: Relay calls (busy + error surfaced; local state only changes on success)

    private func activate(_ alias: EmailAlias) {
        run(alias) { try await env.relay.activate(alias) }
    }

    private func disableAlias(_ alias: EmailAlias) {
        run(alias) { try await env.relay.disable(alias) }
    }

    private func remove(_ alias: EmailAlias) {
        run(alias) { try await env.relay.delete(alias) }
    }

    private func run(_ alias: EmailAlias, _ operation: @escaping () async throws -> Void) {
        busyAliasID = alias.id
        Task {
            defer { busyAliasID = nil }
            do { try await operation() }
            catch is RelayService.Failure {
                errorMessage = appString("Check your connection and iCloud, then try again.")
            } catch {
                errorMessage = appString("Check your connection and iCloud, then try again.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
