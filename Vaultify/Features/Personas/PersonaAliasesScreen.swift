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
    @State private var errorTitle = ""
    @State private var errorMessage: String?
    @State private var missingEmail = false
    @State private var pendingPause: EmailAlias?
    @State private var pendingDelete: EmailAlias?
    @State private var promptReusableLabel = false
    @State private var reusableLabelDraft = ""
    @State private var defaultDomainID = PrivateEmailDomainDefault.domainID
    @State private var paywallContext: LooxPaywallContext?

    private var persona: Persona? { env.repository.activePersona }
    private var gate: PrivateEmailGate { PrivateEmailGate(env) }

    var body: some View {
        List {
            // Contextual capability state (offline ≠ outage ≠ maintenance ≠
            // disabled ≠ retired). Local records below stay visible in EVERY
            // state — only network-dependent actions gate.
            PrivateEmailBannerSection()
            if case .retired = gate.bannerState {
                Section {
                    NavigationLink { AffectedAccountsScreen() } label: {
                        Label { Text("Review affected accounts") } icon: { PolarisIcon(Icons.archive) }
                    }
                }
                .listRowBackground(VaultColors.surface)
            }

            verificationBanner

            Section {
                receiveOnlyBanner
            }
            .listRowBackground(Color.clear)
            // Full row width: with the default list insets the banner's own
            // rounded background rendered narrower than every card below it.
            .listRowInsets(EdgeInsets())

            // PROTAGONIST FIRST (DNA #1): the user comes here for their
            // addresses and whether each one is forwarding — the plumbing
            // (destination inbox, default domain) is configuration and reads
            // below the address lists, not above them.
            if let persona {
                personaAliasSection(persona)
                perSiteSection(persona)
            }

            // Where mail lands — masked overview; full addresses live inside.
            Section("Delivery") {
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

            // Default mail domain for every create flow that doesn't ask
            // (reusable-address alert, editor prefill, item-editor quick
            // action). Reading appliedRevision re-renders this screen when a
            // registry lands AFTER first render — otherwise the picker would
            // stay invisible until the next launch.
            let _ = env.domainRegistry.appliedRevision
            // Hidden with the create affordances: a picker that says "New
            // private addresses use this domain" while nothing can be created
            // contradicts the banner above it.
            if canCreate {
                AliasDomainPickerSection(domainID: $defaultDomainID,
                                         footer: "New private addresses use this domain.")
                    .listRowBackground(VaultColors.surface)
            }
        }
        .navigationTitle(Text("Private Email"))
        // Non-blocking, contextual — never at app startup (INV-CAP-02).
        .task {
            await gate.refresh()
            // A pushed screen, so the root host covers it — no local host needed.
            env.tutorial.startIfNeeded(.privateEmail)
        }
        .sheet(isPresented: $showingPerSiteEditor) {
            if let persona { AliasEditorSheet(persona: persona, onCreated: { activate($0) }) }
        }
        // Pause is reversible later (relay keeps the row) — calm confirmation, not destructive.
        .confirmationDialog("Pause forwarding?", isPresented: pauseBinding,
                            titleVisibility: .visible, presenting: pendingPause) { alias in
            Button("Pause forwarding") { Haptics.tap(); disableAlias(alias) }
        } message: { _ in
            Text("New messages sent to this address will no longer reach your inbox. You can turn forwarding back on later.")
        }
        // Permanent delete: address can never be restored or re-issued (backend tombstone).
        .confirmationDialog("Delete this private address permanently?", isPresented: deleteBinding,
                            titleVisibility: .visible, presenting: pendingDelete) { alias in
            Button("Delete permanently", role: .destructive) { Haptics.error(); remove(alias) }
        } message: { _ in
            Text("This address will stop forwarding and can never be restored or issued to anyone else. Accounts still using this address may no longer be able to send you password resets or important mail.")
        }
        // Title follows the failure: a consent gate and an outage are different
        // problems with different fixes, and a shared heading hid that.
        .alert(Text(verbatim: errorTitle), isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
        .alert(Text("Add an email first"), isPresented: $missingEmail) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Add an email to this identity’s profile. That’s where your aliases forward to.")
        }
        .sheet(item: $paywallContext) { context in NavigationStack { LooxPaywallScreen(context: context) } }
    }

    /// Over-quota upsell gate (§5.3) for BOTH create flows. Retained = active
    /// + paused across the whole vault — the quota follows the subscription
    /// identity, not the persona (§3.2). Pausing/deleting/detail never gates.
    private func guardQuota(_ proceed: () -> Void) {
        guard env.entitlements.purchasesEnabled else { return proceed() }
        let retained = env.repository.aliases.filter { $0.status == .active || $0.status == .paused }.count
        if case .needsUpgrade = LooxGate.canCreateAlias(tier: env.entitlements.tier, retained: retained) {
            paywallContext = .aliasLimit
        } else {
            proceed()
        }
    }

    /// The one prerequisite, said out loud. Creating an address while the
    /// destination is unconfirmed fails at the relay, and the screen used to
    /// carry no hint that a confirmation was outstanding — so the failure
    /// arrived as a surprise, worded like a network problem. Tapping it goes to
    /// the inbox that needs confirming, where the send button lives.
    @ViewBuilder private var verificationBanner: some View {
        if let inbox = gate.unverifiedDestination {
            Section {
                NavigationLink {
                    ForwardingInboxDetailScreen(inboxID: inbox.id)
                } label: {
                    VaultInfoBanner(
                        .warning, icon: Icons.mail,
                        title: "Confirm your forwarding email",
                        verbatimText: appString("Private addresses can’t forward to \(EmailMask.masked(inbox.email)) until you confirm it’s yours. It takes one tap and an email."))
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    /// Standing privacy caution about how forwarding works. It reads as a
    /// WARNING, not as neutral accent context: on the info tint it was visually
    /// identical to the capability banner above it, so a blocked state stacked
    /// two matching accent cards and stopped reading as an alert.
    private var receiveOnlyBanner: some View {
        VaultInfoBanner(.warning, icon: Icons.mail,
                        title: "Mail sent to an active alias forwards to your inbox. Receive-only.",
                        text: "Replies from your destination inbox may reveal your real email address.")
    }

    /// Create affordances render only while creation can actually run — a
    /// visible button that silently swallows the tap (the old `guardEmail`
    /// early-return) reads as a broken screen. The banner above the list
    /// explains WHY creation is gone in every non-available state.
    private var canCreate: Bool { gate.allows(.create) }

    @ViewBuilder private func personaAliasSection(_ persona: Persona) -> some View {
        Section("Reusable addresses") {
            ForEach(env.repository.reusableAliases(forPersona: persona.id)) { alias in
                aliasRow(alias, subtitle: alias.label ?? persona.displayName)
            }
            if canCreate {
                Button {
                    guardQuota { guardEmail(persona) { promptReusableLabel = true } }
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
        }
        .listRowBackground(VaultColors.surface)
    }

    @ViewBuilder private func perSiteSection(_ persona: Persona) -> some View {
        let perSite = env.repository.aliases(forPersona: persona.id).filter { $0.tier == .perSite }
        Section("Site-specific addresses") {
            ForEach(perSite) { alias in
                aliasRow(alias, subtitle: alias.boundDomain)
            }
            if canCreate {
                Button { guardQuota { guardEmail(persona) { showingPerSiteEditor = true } } } label: {
                    Label { Text("Add site-specific address") } icon: { PolarisIcon(Icons.addCircle) }
                }
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    private func aliasRow(_ alias: EmailAlias, subtitle: String?) -> some View {
        // Full working address only when live+active — AliasAddress guarantees it.
        let address = AliasAddress.display(localPart: alias.localPart, status: alias.status,
                                           relayDomain: alias.emailDomain)
        return NavigationLink {
            AliasDetailScreen(aliasID: alias.id)
        } label: {
            // The ADDRESS is the row's payload — it renders whole (an inline
            // trailing status squeezed long addresses into a 2-line wrap mid-
            // word); the forwarding status reads as its own line underneath.
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: address).vaultType(.body).themedForeground(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(verbatim: subtitle).vaultType(.caption).themedForeground(.secondary)
                    }
                    Text(verbatim: statusLabel(alias.status)).vaultType(.caption)
                        .themedForeground(alias.status == .active ? .accent : .secondary)
                }
                Spacer()
                if busyAliasID == alias.id {
                    ProgressView()
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
                                                           label: label.isEmpty ? nil : label,
                                                           domainID: PrivateEmailDomainDefault.domainID),
           let created = env.repository.aliases.first(where: { $0.id == id }) {
            activate(created)
        }
    }

    /// Aliases forward to a real inbox — require one (default inbox or profile
    /// email) before creating. Creation also gates on capability availability
    /// (the banner above explains why when it's blocked).
    private func guardEmail(_ persona: Persona, _ create: () -> Void) {
        guard canCreate else { return }
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
        // "Tap to activate" on a reserved alias is a growth mutation: with the
        // feature off in Settings it must not reach the relay (the create
        // buttons already hide; this row action is the remaining path).
        if gate.isTurnedOffByUser {
            errorTitle = appString("Private Email is off")
            errorMessage = appString("Private Email is turned off in Settings.")
            return
        }
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
                errorTitle = failure.userTitle
                errorMessage = failure.userMessage
                Haptics.error()
            } catch {
                errorTitle = appString("Couldn’t reach the relay")
                errorMessage = appString("Check your connection and iCloud, then try again.")
                Haptics.error()
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

/// One answer to "can Private Email act right now", shared by every screen of
/// the feature (aliases, alias detail, forwarding inboxes, inbox detail) so the
/// banner and the affordances it explains can never disagree.
///
/// It governs RELAY-TOUCHING actions only. Local reads are never gated
/// (INV-CAP-05): saved addresses and inboxes stay visible and manageable in
/// every state, so a banner here is always additive.
struct PrivateEmailGate {
    private let env: AppEnvironment

    init(_ env: AppEnvironment) { self.env = env }

    /// The state the banner explains. Creation is the first operation class the
    /// backend gates, so it is the earliest signal a screen can surface.
    var bannerState: CapabilityAvailability { availability(.create) }

    var messageKey: String? { env.capabilities.messageKeys[.privateEmail] }

    /// The switched-off case specifically — the one state the user can fix.
    var isTurnedOffByUser: Bool { !env.capabilities.userPreference(.privateEmail) }

    func availability(_ operation: CapabilityOperation) -> CapabilityAvailability {
        env.capabilities.availability(.privateEmail, operation: operation)
    }

    func allows(_ operation: CapabilityOperation) -> Bool {
        availability(operation) == .available
    }

    /// The inbox a NEW private address would forward to, when the relay will
    /// refuse to route to it until its owner confirms it. Nil once confirmed,
    /// and nil while the server is not yet enforcing verification.
    ///
    /// This mirrors `RelayService.routedDestination` so the UI can say so BEFORE
    /// the command is sent: the refusal is a consent gate the user can clear in
    /// a minute, and discovering it as a failed create reads like an outage.
    var unverifiedDestination: ForwardingInbox? {
        guard RelayConfig.destinationRoutingRequiresVerification,
              let persona = env.repository.activePersona,
              let email = env.repository.newAliasDestination(for: persona),
              let inbox = env.repository.forwardingInboxes.first(where: { $0.email == email })
        else { return nil }
        return inbox.verificationStatus == .verified ? nil : inbox
    }

    /// Contextual, non-blocking refresh — on screen open or a banner retry,
    /// never at app startup (INV-CAP-02).
    ///
    /// The relay health probe is skipped while the user has the feature switched
    /// off: `.disabledByUser` short-circuits before health is consulted, so the
    /// request could not change what the screen renders. The control-plane
    /// refresh stays unconditional — it is how the app learns the OPERATOR
    /// state, and it is deduped and backoff-aware.
    func refresh() async {
        if !isTurnedOffByUser {
            await CapabilityHealthProbe.probe(.privateEmail, store: env.capabilities)
        }
        await env.controlPlaneRefresher.refreshNow()
    }
}

/// The Private Email capability banner as a list section, so every screen of
/// the feature explains a blocked state identically and offers the same way
/// out. Renders nothing while the feature is available.
struct PrivateEmailBannerSection: View {
    @Environment(AppEnvironment.self) private var env
    /// Nil on the iPad/Mac sidebar, where screens navigate through SwiftUI
    /// paths instead; `push` is a no-op there.
    @Environment(AppNavigator.self) private var navigator: AppNavigator?

    var body: some View {
        let gate = PrivateEmailGate(env)
        if gate.bannerState != .available {
            Section {
                CapabilityBannerView(availability: gate.bannerState,
                                     messageKey: gate.messageKey,
                                     onOpenSettings: openSettings,
                                     onRetry: { Task { await gate.refresh() } })
            }
            .listRowBackground(Color.clear)
            // Full row width, matching the cards below (the default list insets
            // render the banner's own rounded background narrower).
            .listRowInsets(EdgeInsets())
        }
    }

    /// "Open Settings" is offered only where it can actually go there: the
    /// compact-iOS shell pushes Settings full-screen (the shared value route is
    /// registered on the Home stack and would not resolve from here). Nil on the
    /// iPad/Mac sidebar, so the banner shows no dead affordance.
    private var openSettings: (() -> Void)? {
        guard let navigator else { return nil }
        return { navigator.push { SettingsScreen() } }
    }
}
