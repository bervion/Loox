import SwiftUI

struct AliasDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let aliasID: String
    @State private var busy = false
    @State private var copied = false
    @State private var errorTitle = ""
    @State private var errorMessage: String?
    @State private var errorOffersReset = false
    @State private var confirmDelete = false
    @State private var confirmPause = false
    @State private var editingLabel = false
    @State private var labelDraft = ""
    @State private var showingLoginPicker = false
    @State private var verificationToken: UUID?

    private var alias: EmailAlias? {
        env.repository.aliases.first { $0.id == aliasID && $0.personaId == env.repository.activePersona?.id }
    }
    private var persona: Persona? { env.repository.activePersona }
    private var gate: PrivateEmailGate { PrivateEmailGate(env) }
    private var visibleInboxIDs: Set<String> {
        guard let alias else { return [] }
        var ids = Set<String>()
        if let id = alias.forwardingInboxID { ids.insert(id) }
        if let persona, let inbox = env.repository.defaultInbox(for: persona) { ids.insert(inbox.id) }
        for inbox in env.repository.forwardingInboxes where inbox.email == alias.forwardingTarget { ids.insert(inbox.id) }
        return ids
    }

    var body: some View {
        Group {
            if let alias { content(alias) }
            else { Color.clear.onAppear { dismiss() } }
        }
        .navigationTitle(Text("Private address"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let alias {
                ToolbarItem(placement: .platformPrimaryAction) {
                    Menu {
                        Button { labelDraft = alias.label ?? ""; editingLabel = true } label: {
                            Label { Text("Edit label") } icon: { VaultIcon(Icons.edit) }
                        }
                        Button { showingLoginPicker = true } label: {
                            Label { Text("Link a login") } icon: { VaultIcon(Icons.add) }
                        }.disabled(alias.resolvedAddress == nil)
                        if alias.status == .active {
                            Button { confirmPause = true } label: {
                                Label { Text("Pause forwarding") } icon: { VaultIcon(Icons.hide) }
                            }.disabled(busy || !gate.allows(.revoke))
                        }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label { Text("Delete permanently") } icon: { VaultIcon(Icons.trash) }
                        }.disabled(busy || !gate.allows(.delete))
                    } label: {
                        VaultIcon(Icons.moreHorizontal, size: Metric.iconUtility)
                            .frame(width: Metric.hitMin, height: Metric.hitMin)
                    }.accessibilityLabel(Text("Manage address"))
                }
            }
        }
        .relayFailureAlert(title: errorTitle, message: errorMessage, isPresented: errorBinding,
                           offersReset: errorOffersReset) { resetPrivateEmail() }
        .alert("Edit label", isPresented: $editingLabel) {
            TextField("Label", text: $labelDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveLabel() }
        }
        .confirmationDialog("Pause forwarding?", isPresented: $confirmPause, titleVisibility: .visible) {
            Button("Pause forwarding") {
                guard let alias else { return }
                Haptics.tap()
                run { try await env.relay.disable(alias) }
            }
        } message: {
            Text("This pauses mail for every service using this address. Linked vault items stay unchanged.")
        }
        .confirmationDialog("Delete this private address permanently?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                guard let alias else { return }
                Haptics.error()
                run { try await env.relay.delete(alias) }
            }
        } message: {
            Text("This address will stop forwarding and can never be restored or issued to anyone else. Accounts still using this address may no longer be able to send you password resets or important mail.")
        }
        .sheet(isPresented: $showingLoginPicker) { AliasLoginPickerSheet(aliasID: aliasID) }
        .onAppear { verificationToken = env.destinationVerification.register(visibleInboxIDs, priority: true) }
        .onChange(of: visibleInboxIDs) { _, ids in
            if let verificationToken { env.destinationVerification.update(verificationToken, inboxIDs: ids) }
        }
        .onChange(of: env.repository.activePersona?.id) { _, _ in dismiss() }
        .onDisappear {
            copied = false
            if let verificationToken { env.destinationVerification.unregister(verificationToken) }
            verificationToken = nil
        }
        .task(id: copied) {
            if copied {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { copied = false }
            }
        }
    }

    private func content(_ alias: EmailAlias) -> some View {
        List {
            PrivateEmailBannerSection()
            Section {
                VStack(alignment: .leading, spacing: Space.s3) {
                    if let label = alias.label, !label.isEmpty {
                        Text(verbatim: label).vaultType(.headline).themedForeground(.secondaryBody)
                    }
                    Text(verbatim: alias.resolvedAddress ?? appString("Domain unavailable"))
                        .vaultType(.section).themedForeground(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: PrivateEmailStatusPresentation.label(alias)).vaultType(.subhead)
                        .themedForeground(PrivateEmailStatusPresentation.role(alias))
                    if let address = alias.resolvedAddress {
                        if alias.status == .reserved || alias.status == .draft {
                            Button { run { try await env.relay.activate(alias) } } label: {
                                Text(alias.backendMinted ? "Finish setup" : "Activate address")
                                    .frame(maxWidth: .infinity)
                                    .prominentButtonLoading(busy, tint: Color.platformBackground)
                            }.buttonStyle(.themedProminent)
                                .disabled(busy || !gate.allows(alias.backendMinted ? .mutate : .create))
                        } else if alias.status == .paused || alias.status == .disabled {
                            Button { run { try await env.relay.activate(alias) } } label: {
                                Text("Resume forwarding").frame(maxWidth: .infinity)
                                    .prominentButtonLoading(busy, tint: Color.platformBackground)
                            }.buttonStyle(.themedProminent).disabled(busy || !gate.allows(.mutate))
                        } else {
                            Button { copy(address) } label: {
                                Label { Text(copied ? "Copied" : "Copy address") } icon: { CopyMorphIcon(copied: copied) }
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(.themedProminent)
                        }
                    } else {
                        Text("This domain is not available locally. Connect to refresh its signed mapping.")
                            .vaultType(.footnote).themedForeground(.secondaryBody)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.vertical, Space.s2)
            }.listRowBackground(VaultColors.surface)

            Section {
                NavigationLink { AliasLinkedServicesScreen(personaID: alias.personaId, aliasID: alias.id) } label: {
                    HStack(spacing: Space.s3) {
                        VaultIcon(Icons.globe, size: Metric.iconInline).themedForeground(.iconSecondary)
                        Text("Linked services").vaultType(.body)
                        Spacer(minLength: Space.s2)
                        Text(verbatim: String(env.repository.linkedServices(for: alias.personaId, aliasID: alias.id).count))
                            .vaultType(.subhead).themedForeground(.secondaryBody)
                    }.frame(minHeight: Metric.hitMin)
                }
                if let website = alias.boundDomain, !website.isEmpty {
                    PrivateEmailFieldValue(label: "Website", value: website)
                }
            }.listRowBackground(VaultColors.surface)

            Section("Receiving mail") {
                if let checkpoint = alias.forwardingTarget, alias.backendMinted {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("Last confirmed destination").vaultType(.footnote).themedForeground(.secondaryBody)
                        PrivateEmailRecipientValue(email: checkpoint)
                    }
                    if let inbox = env.repository.forwardingInboxes.first(where: { $0.email == checkpoint }) {
                        NavigationLink { ForwardingInboxDetailScreen(inboxID: inbox.id) } label: { Text("Inbox details") }
                    }
                } else {
                    Text("Not forwarding yet").vaultType(.body).themedForeground(.secondaryBody)
                }
                if let desired = env.repository.resolvedDestination(for: alias),
                   !alias.backendMinted || desired != alias.forwardingTarget {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("Selected inbox").vaultType(.footnote).themedForeground(.secondaryBody)
                        PrivateEmailRecipientValue(email: desired)
                        if alias.backendMinted {
                            Text("Forwarding update pending").vaultType(.footnote).themedForeground(.warningBody)
                        }
                    }
                }
                if alias.backendMinted,
                   let desiredInbox = desiredInbox(alias), desiredInbox.email != alias.forwardingTarget {
                    Button("Apply inbox change") { run { try await env.relay.setInbox(desiredInbox, for: alias) } }
                        .disabled(busy || !gate.allows(.mutate))
                }
                Menu {
                    ForEach(availableInboxes(alias)) { inbox in
                        Button { run { try await env.relay.setInbox(inbox, for: alias) } } label: {
                            Text(verbatim: inbox.label.flatMap { $0.isEmpty ? nil : $0 } ?? EmailMask.masked(inbox.email))
                        }
                    }
                } label: {
                    Label { Text("Choose receiving inbox") } icon: { VaultIcon(Icons.mail) }
                }.disabled(busy || !gate.allows(.mutate) || availableInboxes(alias).isEmpty)
                NavigationLink { ForwardingInboxScreen() } label: { Text("Manage forwarding inboxes") }
            }.listRowBackground(VaultColors.surface)

            PrivateEmailReceiveOnlySection(hasActionableNotice: gate.bannerState != .available)
        }.themedFormBackground()
    }

    private func desiredInbox(_ alias: EmailAlias) -> ForwardingInbox? {
        if let id = alias.forwardingInboxID { return env.repository.inbox(id: id) }
        return persona.flatMap { env.repository.defaultInbox(for: $0) }
    }

    private func availableInboxes(_ alias: EmailAlias) -> [ForwardingInbox] {
        env.repository.forwardingInboxes.filter { $0.source == .manual || $0.personaId == alias.personaId || $0.isDefault }
    }

    private func copy(_ address: String) {
        env.clipboard.copy(address, label: appString("private email"), sensitive: false)
        copied = true
    }

    private func saveLabel() {
        guard var live = alias else { return }
        let label = labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        live.label = label.isEmpty ? nil : label
        do { try env.repository.updateAlias(live) }
        catch {
            errorTitle = appString("Couldn’t update the address")
            errorMessage = appString("The address changed. Open it again and retry.")
            Haptics.error()
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        guard !busy, let personaID = alias?.personaId else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() }
            catch is CancellationError { }
            catch let failure as VaultRepository.AliasLinkFailure {
                guard env.repository.activePersona?.id == personaID else { return }
                errorTitle = appString("Check the linked login"); errorMessage = failure.userMessage
                errorOffersReset = false
                Haptics.error()
            }
            catch let failure as RelayService.Failure {
                guard env.repository.activePersona?.id == personaID else { return }
                errorTitle = failure.userTitle; errorMessage = failure.userMessage
                errorOffersReset = failure.offersPrivateEmailReset
                Haptics.error()
            } catch {
                guard env.repository.activePersona?.id == personaID else { return }
                errorTitle = appString("Couldn’t update the address")
                errorMessage = appString("Check your connection and retry. This address is kept for you.")
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
