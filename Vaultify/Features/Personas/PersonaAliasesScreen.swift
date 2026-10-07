import SwiftUI

/// The addresses are the protagonist; linked Login records and receiving
/// settings have their own destinations and remain usable offline.
struct PersonaAliasesScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingEditor = false
    @State private var createdAliasID: String?
    @State private var defaultDomainID = PrivateEmailDomainDefault.domainID
    @State private var verificationInboxID: String?
    @State private var verificationToken: UUID?
    @State private var paywallContext: LooxPaywallContext?

    private var persona: Persona? { env.repository.activePersona }
    private var gate: PrivateEmailGate { PrivateEmailGate(env) }
    private var visibleInboxIDs: Set<String> {
        guard let persona else { return [] }
        var ids = Set(env.repository.defaultInbox(for: persona).map { [$0.id] } ?? [])
        for alias in env.repository.aliases(forPersona: persona.id) {
            if let id = alias.forwardingInboxID { ids.insert(id) }
            for inbox in env.repository.forwardingInboxes where inbox.email == alias.forwardingTarget {
                ids.insert(inbox.id)
            }
        }
        return ids
    }

    var body: some View {
        List {
            PrivateEmailBannerSection()
            if let persona {
                addressSection(persona, tier: .perSite, title: "Addresses for services")
                addressSection(persona, tier: .persona, title: "Addresses for many places")
                Section {
                    NavigationLink { AliasLinkedServicesScreen(personaID: persona.id) } label: {
                        HStack(spacing: Space.s3) {
                            VaultIcon(Icons.globe, size: Metric.iconInline).themedForeground(.iconSecondary)
                            Text("Linked services").vaultType(.body).themedForeground(.primary)
                            Spacer(minLength: Space.s2)
                            Text(verbatim: String(env.repository.linkedServices(for: persona.id).count))
                                .vaultType(.subhead).themedForeground(.secondaryBody)
                        }.frame(minHeight: Metric.hitMin)
                    }
                }.listRowBackground(VaultColors.surface)
                if gate.allows(.create) && !AuxiliaryDomainRegistry.creatableEmailDomains.isEmpty {
                    Section {
                        Button { guardQuota { showingEditor = true } } label: {
                            Label { Text("Create private email") } icon: { VaultIcon(Icons.add, size: Metric.iconInline) }
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.themedProminent)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                receivingSection(persona)
            }

            let _ = env.domainRegistry.appliedRevision
            if gate.allows(.create) {
                AliasDomainPickerSection(domainID: $defaultDomainID, footer: "New private addresses use this domain.")
                    .listRowBackground(VaultColors.surface)
            }
            if gate.bannerState == .available, let inbox = gate.unverifiedDestination {
                Section {
                    VaultInfoBanner(.warning, title: "Confirm your inbox",
                        verbatimText: appString("Confirm \(EmailMask.masked(inbox.email)) to receive forwarded mail."),
                        actionLabel: "Confirm email", action: { verificationInboxID = inbox.id })
                        .subtle().inList()
                }
            }
            PrivateEmailReceiveOnlySection(hasActionableNotice: gate.bannerState != .available || gate.unverifiedDestination != nil)
            if case .retired = gate.bannerState {
                Section {
                    NavigationLink { AffectedAccountsScreen() } label: {
                        Label { Text("Review affected accounts") } icon: { VaultIcon(Icons.archive) }
                    }
                }.listRowBackground(VaultColors.surface)
            }
        }
        .themedFormBackground()
        .navigationTitle(Text("Private Email"))
        .navigationDestination(item: $verificationInboxID) { ForwardingInboxDetailScreen(inboxID: $0) }
        .navigationDestination(item: $createdAliasID) { AliasDetailScreen(aliasID: $0) }
        .task {
            await gate.refresh()
            env.tutorial.startIfNeeded(.privateEmail)
        }
        .onAppear { verificationToken = env.destinationVerification.register(visibleInboxIDs) }
        .onChange(of: visibleInboxIDs) { _, ids in
            if let verificationToken { env.destinationVerification.update(verificationToken, inboxIDs: ids) }
        }
        .onChange(of: env.repository.activePersona?.id) { _, _ in
            createdAliasID = nil; verificationInboxID = nil; showingEditor = false
        }
        .onDisappear {
            env.tutorial.cancelPendingStart()
            if let verificationToken { env.destinationVerification.unregister(verificationToken) }
            verificationToken = nil
        }
        .sheet(isPresented: $showingEditor) {
            if let persona { AliasEditorSheet(persona: persona, onCreated: { createdAliasID = $0.id }) }
        }
        .sheet(item: $paywallContext) { context in NavigationStack { LooxPaywallScreen(context: context) } }
    }

    private func addressSection(_ persona: Persona, tier: AliasTier, title: LocalizedStringKey) -> some View {
        let aliases = env.repository.aliases(forPersona: persona.id).filter { $0.tier == tier }
        return Section {
            if aliases.isEmpty {
                Text(tier == .perSite ? "Give each service its own address." : "Keep one address for several services.")
                    .vaultType(.subhead).themedForeground(.secondaryBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(aliases) { alias in
                NavigationLink { AliasDetailScreen(aliasID: alias.id) } label: {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(verbatim: alias.resolvedAddress ?? appString("Domain unavailable"))
                            .vaultType(.body).themedForeground(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let label = alias.label ?? alias.boundDomain, !label.isEmpty {
                            Text(verbatim: label).vaultType(.caption).themedForeground(.secondaryBody)
                        }
                        Text(verbatim: PrivateEmailStatusPresentation.label(alias))
                            .vaultType(.caption).themedForeground(PrivateEmailStatusPresentation.role(alias))
                    }.frame(minHeight: Metric.hitMin, alignment: .leading)
                }
            }
        } header: { Text(title) }
        .listRowBackground(VaultColors.surface)
    }

    private func receivingSection(_ persona: Persona) -> some View {
        Section("Receiving mail") {
            if let inbox = env.repository.defaultInbox(for: persona) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("For new addresses").vaultType(.footnote).themedForeground(.secondaryBody)
                    PrivateEmailRecipientValue(email: inbox.email)
                }
                NavigationLink { ForwardingInboxDetailScreen(inboxID: inbox.id) } label: {
                    Text("Inbox details")
                }
            } else {
                NavigationLink { ForwardingInboxScreen() } label: { Text("Add a forwarding inbox") }
            }
            NavigationLink { ForwardingInboxScreen() } label: { Text("Manage forwarding inboxes") }
        }.listRowBackground(VaultColors.surface)
    }

    private func guardQuota(_ proceed: () -> Void) {
        guard env.entitlements.purchasesEnabled else { return proceed() }
        let retained = env.repository.aliases.filter { $0.status == .active || $0.status == .paused }.count
        if case .needsUpgrade = LooxGate.canCreateAlias(tier: env.entitlements.tier, retained: retained) {
            paywallContext = .aliasLimit
        } else { proceed() }
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
        #if DEBUG
        guard !env.uiTestConfiguration.isEnabled, !CloudSyncService.isHostingUnitTests else { return }
        #endif
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
