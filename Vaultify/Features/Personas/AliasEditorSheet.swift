import SwiftUI

/// A local reservation is a retry checkpoint, including a minted namespace.
/// Failures leave this form and the exact address available for retry.
struct AliasEditorSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let persona: Persona
    var initialTier: AliasTier = .perSite
    var onCreated: ((EmailAlias) -> Void)?

    @State private var tier: AliasTier = .perSite
    @State private var selectedItemID: String?
    @State private var selectedInboxID: String?
    @State private var domainID = PrivateEmailDomainDefault.domainID
    @State private var label = ""
    @State private var website = ""
    @State private var reservedAliasID: String?
    @State private var busy = false
    @State private var errorTitle = ""
    @State private var errorMessage: String?
    @State private var errorOffersReset = false
    @State private var verificationToken: UUID?
    @State private var initialized = false
    @State private var loginNeedsReview = false

    private var loginItems: [VaultItem] {
        env.repository.items(for: persona).filter { $0.category == .login && $0.sharedOrigin == nil }
    }
    private var inboxes: [ForwardingInbox] {
        env.repository.forwardingInboxes.filter { $0.source == .manual || $0.personaId == persona.id || $0.isDefault }
    }
    private var selectedInbox: ForwardingInbox? {
        if let reservation = liveReservation, let pinned = reservation.forwardingInboxID {
            return inboxes.first { $0.id == pinned }
        }
        if let selectedInboxID { return inboxes.first { $0.id == selectedInboxID } }
        return env.repository.defaultInbox(for: persona)
    }
    private var visibleInboxIDs: Set<String> { Set(selectedInbox.map { [$0.id] } ?? []) }
    private var liveReservation: EmailAlias? { env.repository.aliases.first { $0.id == reservedAliasID } }
    private var gate: PrivateEmailGate { PrivateEmailGate(env) }
    private var needsVerification: Bool {
        RelayConfig.destinationRoutingRequiresVerification && selectedInbox?.verificationStatus != .verified
    }

    var body: some View {
        VaultSheetScaffold(title: "Create private email") {
            Form {
                PrivateEmailBannerSection()
                Section {
                    Menu {
                        Button("For a service") { tier = .perSite; Haptics.tap() }
                        Button("Use in many places") { tier = .persona; Haptics.tap() }
                    } label: {
                        PrivateEmailChoiceLabel(label: "Address type",
                            value: appString(tier == .perSite ? "For a service" : "Use in many places"))
                    }
                    TextField("Label (optional)", text: $label)
                    if tier == .perSite {
                        TextField("Website (optional)", text: $website)
                            .platformKeyboardType(.url).platformAutocapitalization(.never).autocorrectionDisabled()
                        Menu {
                            Button("Link later") { selectedItemID = nil; Haptics.tap() }
                            ForEach(loginItems) { item in
                                Button { selectedItemID = item.id; Haptics.tap() } label: { Text(verbatim: item.title) }
                            }
                        } label: {
                            PrivateEmailChoiceLabel(label: "Link a login",
                                value: loginItems.first(where: { $0.id == selectedItemID })?.title ?? appString("Link later"))
                        }
                    }
                } footer: { Text("You can create an address now and link a saved login later.").themedForeground(.secondaryBody) }
                .disabled(reservedAliasID != nil || busy)
                .listRowBackground(VaultColors.surface)

                if loginNeedsReview, let selectedItemID {
                    Section {
                        NavigationLink { ItemDetailScreen(itemID: selectedItemID) } label: { Text("Open login") }
                    }.listRowBackground(VaultColors.surface)
                }

                let _ = env.domainRegistry.appliedRevision
                if let reservation = liveReservation {
                    Section {
                        PrivateEmailFieldValue(label: "Reserved address",
                                               value: reservation.resolvedAddress ?? appString("Domain unavailable"))
                    } footer: { Text("Retry continues setting up this address.").themedForeground(.secondaryBody) }
                    .listRowBackground(VaultColors.surface)
                } else {
                    AliasDomainPickerSection(domainID: $domainID).disabled(busy)
                        .listRowBackground(VaultColors.surface)
                }

                Section("Forwarding inbox") {
                    if inboxes.count > 1 {
                        Menu {
                            Button("Default inbox") { selectedInboxID = nil; Haptics.tap() }
                            ForEach(inboxes) { inbox in
                                Button { selectedInboxID = inbox.id; Haptics.tap() } label: {
                                    Text(verbatim: inbox.label.flatMap { $0.isEmpty ? nil : $0 } ?? EmailMask.masked(inbox.email))
                                }
                            }
                        } label: {
                            PrivateEmailChoiceLabel(label: "Receive at", value: selectedInbox?.label.flatMap {
                                $0.isEmpty ? nil : $0
                            } ?? selectedInbox.map { EmailMask.masked($0.email) } ?? appString("Default inbox"))
                        }.disabled(reservedAliasID != nil || busy)
                    }
                    if let inbox = selectedInbox {
                        PrivateEmailRecipientValue(email: inbox.email)
                        NavigationLink { ForwardingInboxDetailScreen(inboxID: inbox.id) } label: {
                            Text(inbox.verificationStatus == .verified ? "Inbox details" : "Confirm email")
                        }
                    } else {
                        NavigationLink { ForwardingInboxScreen() } label: { Text("Add a forwarding inbox") }
                    }
                }.listRowBackground(VaultColors.surface)

                Section {
                    if needsVerification, let inbox = selectedInbox {
                        NavigationLink { ForwardingInboxDetailScreen(inboxID: inbox.id) } label: {
                            Text("Confirm email").frame(maxWidth: .infinity)
                        }.buttonStyle(.themedProminent)
                    } else {
                        Button { create() } label: {
                            Text(reservedAliasID == nil ? "Create address" : "Retry setup")
                                .frame(maxWidth: .infinity)
                                .prominentButtonLoading(busy, tint: Color.platformBackground)
                        }
                        .buttonStyle(.themedProminent)
                        .disabled(busy || selectedInbox == nil || !gate.allows(liveReservation?.backendMinted == true ? .mutate : .create)
                                  || (reservedAliasID == nil && !AuxiliaryDomainRegistry.creatableEmailDomains.contains(where: { $0.id == domainID })))
                    }
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                PrivateEmailReceiveOnlySection(hasActionableNotice: gate.bannerState != .available || needsVerification)
            }
        }
        .relayFailureAlert(title: errorTitle, message: errorMessage, isPresented: errorBinding,
                           offersReset: errorOffersReset) { resetPrivateEmail() }
        .onAppear {
            if !initialized { tier = initialTier; initialized = true }
            verificationToken = env.destinationVerification.register(visibleInboxIDs, priority: true)
        }
        .onChange(of: visibleInboxIDs) { _, ids in
            if let verificationToken { env.destinationVerification.update(verificationToken, inboxIDs: ids) }
        }
        .onChange(of: env.repository.activePersona?.id) { _, id in if id != persona.id { dismiss() } }
        .onDisappear {
            if let verificationToken { env.destinationVerification.unregister(verificationToken) }
            verificationToken = nil
        }
        .interactiveDismissDisabled(busy)
    }

    private func create() {
        guard !busy, env.repository.activePersona?.id == persona.id, let inbox = selectedInbox else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                if tier == .perSite, let selectedItemID {
                    guard let login = loginItems.first(where: { $0.id == selectedItemID }) else {
                        throw VaultRepository.AliasLinkFailure.unavailableLogin
                    }
                    if let field = try AliasWriteback.readableField(on: login), !field.value.isEmpty,
                       field.value != liveReservation?.resolvedAddress {
                        throw VaultRepository.AliasLinkFailure.field(.conflictingAddress)
                    }
                }
                loginNeedsReview = false
                if reservedAliasID == nil {
                    selectedInboxID = inbox.id
                    let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedWebsite = website.trimmingCharacters(in: .whitespacesAndNewlines)
                    let hostname = trimmedWebsite.isEmpty ? nil
                        : URL(string: trimmedWebsite.contains("://") ? trimmedWebsite : "https://" + trimmedWebsite)?.host
                    if tier == .perSite && !trimmedWebsite.isEmpty && hostname == nil {
                        errorTitle = appString("Check the website")
                        errorMessage = appString("Enter a website such as github.com.")
                        return
                    }
                    if tier == .persona {
                        reservedAliasID = try env.repository.createPersonaAlias(
                            for: persona, label: trimmedLabel.isEmpty ? nil : trimmedLabel,
                            forwardingInboxID: inbox.id, domainID: domainID)
                    } else {
                        reservedAliasID = try env.repository.createPerSiteAlias(
                            for: persona, boundItemId: selectedItemID, domain: hostname, domainID: domainID,
                            label: trimmedLabel.isEmpty ? nil : trimmedLabel, forwardingInboxID: inbox.id)
                    }
                }
                guard let checkpoint = liveReservation else { throw VaultRepository.AliasMutationError.staleRecord }
                try await env.relay.activate(checkpoint)
                guard env.repository.activePersona?.id == persona.id, let live = liveReservation else { return }
                onCreated?(live)
                dismiss()
            } catch let failure as VaultRepository.AliasLinkFailure {
                loginNeedsReview = true
                errorTitle = appString("Check the linked login"); errorMessage = failure.userMessage
                errorOffersReset = false
                Haptics.error()
            } catch let failure as AliasWriteback.Failure {
                loginNeedsReview = true
                errorTitle = appString("Check the linked login")
                errorMessage = VaultRepository.AliasLinkFailure.field(failure).userMessage
                errorOffersReset = false
                Haptics.error()
            } catch let failure as RelayService.Failure {
                errorTitle = failure.userTitle; errorMessage = failure.userMessage
                errorOffersReset = failure.offersPrivateEmailReset
                Haptics.error()
            } catch {
                errorTitle = appString("Couldn’t create the address")
                errorMessage = appString("Your changes are still here. Try saving again.")
                Haptics.error()
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil; errorOffersReset = false } })
    }

    private func resetPrivateEmail() {
        Task {
            let result = await PrivateEmailReset.run(using: env.relay)
            errorTitle = result.title; errorMessage = result.message; errorOffersReset = result.offersReset
        }
    }
}
