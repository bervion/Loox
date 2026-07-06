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
    @State private var missingEmail = false
    @State private var pendingPause: EmailAlias?
    @State private var pendingDelete: EmailAlias?
    @State private var promptReusableLabel = false
    @State private var reusableLabelDraft = ""

    private var persona: Persona? { env.repository.activePersona }

    var body: some View {
        List {
            // Contextual capability state (offline ≠ outage ≠ maintenance ≠
            // disabled ≠ retired). Local records below stay visible in EVERY
            // state — only network-dependent actions gate.
            let createState = env.capabilities.availability(.privateEmail, operation: .create)
            if createState != .available {
                Section {
                    CapabilityBannerView(availability: createState) { probe() }
                }
                .listRowBackground(Color.clear)
            }
            if case .retired = createState {
                Section {
                    NavigationLink { AffectedAccountsScreen() } label: {
                        Label { Text("Review affected accounts") } icon: { PolarisIcon(Icons.archive) }
                    }
                }
                .listRowBackground(VaultColors.surface)
            }

            Section {
                warningBanner
            }
            .listRowBackground(Color.clear)

            // Where mail lands — masked overview; full addresses live inside.
            Section {
                NavigationLink { ForwardingInboxScreen() } label: {
                    if let persona, let dest = env.repository.newAliasDestination(for: persona) {
                        LabeledContent { Text(verbatim: EmailMask.masked(dest)) }
                            label: { Text("Forwarding to") }
                    } else {
                        Text("Forwarding inboxes")
                    }
                }
            }
            .listRowBackground(VaultColors.surface)

            if let persona {
                personaAliasSection(persona)
                perSiteSection(persona)
            }
        }
        .navigationTitle(Text("Private Email"))
        // Non-blocking, contextual — never at app startup (INV-CAP-02).
        .task { probe() }
        .sheet(isPresented: $showingPerSiteEditor) {
            if let persona { AliasEditorSheet(persona: persona, onCreated: { activate($0) }) }
        }
        // Pause is reversible later (relay keeps the row) — calm confirmation, not destructive.
        .confirmationDialog("Pause forwarding?", isPresented: pauseBinding,
                            titleVisibility: .visible, presenting: pendingPause) { alias in
            Button("Pause forwarding") { disableAlias(alias) }
        } message: { _ in
            Text("New messages sent to this address will no longer reach your inbox. You can turn forwarding back on later.")
        }
        // Permanent delete: address can never be restored or re-issued (backend tombstone).
        .confirmationDialog("Delete this private address permanently?", isPresented: deleteBinding,
                            titleVisibility: .visible, presenting: pendingDelete) { alias in
            Button("Delete permanently", role: .destructive) { remove(alias) }
        } message: { _ in
            Text("This address will stop forwarding and can never be restored or issued to anyone else. Accounts still using this address may no longer be able to send you password resets or important mail.")
        }
        .alert(Text("Couldn’t reach the relay"), isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .alert(Text("Add an email first"), isPresented: $missingEmail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add an email to this identity’s profile — that’s where your aliases forward to.")
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
        Section("Reusable addresses") {
            ForEach(env.repository.reusableAliases(forPersona: persona.id)) { alias in
                aliasRow(alias, subtitle: alias.label ?? persona.displayName)
            }
            Button {
                guardEmail(persona) { promptReusableLabel = true }
            } label: {
                Label { Text("Create reusable address") } icon: { PolarisIcon(Icons.addCircle) }
            }
            .alert("New reusable address", isPresented: $promptReusableLabel) {
                TextField("Label", text: $reusableLabelDraft)
                Button("Cancel", role: .cancel) { reusableLabelDraft = "" }
                Button("Save") { createReusable(persona) }
            } message: {
                Text("Optional label like “Clients”.")
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    @ViewBuilder private func perSiteSection(_ persona: Persona) -> some View {
        let perSite = env.repository.aliases(forPersona: persona.id).filter { $0.tier == .perSite }
        Section("Site-specific addresses") {
            ForEach(perSite) { alias in
                aliasRow(alias, subtitle: alias.boundDomain)
            }
            Button { guardEmail(persona) { showingPerSiteEditor = true } } label: {
                Label { Text("Add site-specific address") } icon: { PolarisIcon(Icons.addCircle) }
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    private func aliasRow(_ alias: EmailAlias, subtitle: String?) -> some View {
        // Full working address only when live+active — AliasAddress guarantees it.
        let address = AliasAddress.display(localPart: alias.localPart, status: alias.status,
                                           relayDomain: RelayConfig.emailDomain)
        return NavigationLink {
            AliasDetailScreen(aliasID: alias.id)
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
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { pendingDelete = alias } label: {
                Label { Text("Delete") } icon: { PolarisIcon(Icons.trash) }
            }
            if alias.status != .disabled {
                Button { pendingPause = alias } label: {
                    Label { Text("Pause") } icon: { PolarisIcon(Icons.hide) }
                }
            }
        }
    }

    private func createReusable(_ persona: Persona) {
        let label = reusableLabelDraft.trimmingCharacters(in: .whitespaces)
        reusableLabelDraft = ""
        if let id = try? env.repository.createPersonaAlias(for: persona,
                                                           label: label.isEmpty ? nil : label),
           let created = env.repository.aliases.first(where: { $0.id == id }) {
            activate(created)
        }
    }

    private func probe() {
        Task { await CapabilityHealthProbe.probe(.privateEmail, store: env.capabilities) }
    }

    /// Aliases forward to a real inbox — require one (default inbox or profile
    /// email) before creating. Creation also gates on capability availability
    /// (the banner above explains why when it's blocked).
    private func guardEmail(_ persona: Persona, _ create: () -> Void) {
        guard env.capabilities.availability(.privateEmail, operation: .create) == .available else { return }
        if env.repository.newAliasDestination(for: persona) == nil { missingEmail = true }
        else { create() }
    }

    private func statusLabel(_ status: AliasStatus) -> String {
        switch status {
        case .active:   return appString("Forwarding active")
        case .reserved: return appString("Tap to activate")
        case .disabled: return appString("Forwarding paused")
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
            catch let failure as RelayService.Failure {
                errorMessage = failure.userMessage
            } catch {
                errorMessage = appString("Check your connection and iCloud, then try again.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var pauseBinding: Binding<Bool> {
        Binding(get: { pendingPause != nil }, set: { if !$0 { pendingPause = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}
