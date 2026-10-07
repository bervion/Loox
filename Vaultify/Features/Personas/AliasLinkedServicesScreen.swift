import SwiftUI

/// Vault-owned service associations. These are saved Login items, not an
/// account-discovery claim about Facebook/GitHub or any external provider.
struct AliasLinkedServicesScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let personaID: String
    var aliasID: String? = nil
    @State private var reviewingLegacy = false
    @State private var linkingLogin = false

    private var links: [AliasLinkedService] {
        env.repository.linkedServices(for: personaID, aliasID: aliasID)
    }

    var body: some View {
        List {
            if let aliasID, let alias = env.repository.aliases.first(where: { $0.id == aliasID }),
               let address = alias.resolvedAddress {
                Section {
                    Text(verbatim: address).vaultType(.body).themedForeground()
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }.listRowBackground(VaultColors.surface)
            }
            Section {
                if links.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("No linked services").vaultType(.headline).themedForeground()
                        Text("Link a saved login to see which services use this private address.")
                            .vaultType(.callout).themedForeground(.secondaryBody)
                    }.padding(.vertical, Space.s2)
                } else {
                    ForEach(links) { link in
                        NavigationLink {
                            AliasLinkedServiceDetailScreen(link: link)
                        } label: { AliasLinkedServiceRow(link: link) }
                    }
                }
            } footer: {
                Text("Only logins linked in this vault appear here. Loox does not discover accounts on other services.").themedForeground(.secondaryBody)
            }.listRowBackground(VaultColors.surface)
            if aliasID != nil {
                Section {
                    Button { linkingLogin = true } label: {
                        Label { Text("Link a login") } icon: { VaultIcon(Icons.addCircle) }
                            .frame(minHeight: Metric.hitMin)
                    }
                }.listRowBackground(VaultColors.surface)
            }
            Section {
                Button { reviewingLegacy = true } label: {
                    Label { Text("Review saved logins") } icon: { VaultIcon(Icons.search) }
                        .frame(minHeight: Metric.hitMin)
                }
            } footer: {
                Text("Review older logins that saved this address as their email or username. Nothing changes until you choose Link.").themedForeground(.secondaryBody)
            }.listRowBackground(VaultColors.surface)
        }
        .navigationTitle(Text("Linked services"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .themedFormBackground()
        .sheet(isPresented: $reviewingLegacy) {
            AliasLegacyReviewSheet(personaID: personaID, aliasID: aliasID)
        }
        .sheet(isPresented: $linkingLogin) {
            if let aliasID { AliasLoginPickerSheet(aliasID: aliasID) }
        }
        .onChange(of: env.repository.activePersona?.id) { _, id in
            if id != personaID { dismiss() }
        }
    }
}

private struct AliasLinkedServiceRow: View {
    let link: AliasLinkedService
    var body: some View {
        HStack(spacing: Space.s3) {
            VaultIcon(Icons.globe, size: Metric.iconUtility).themedForeground(.iconSecondary)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text(verbatim: link.itemTitle).vaultType(.body).themedForeground()
                    .fixedSize(horizontal: false, vertical: true)
                if let website = link.website {
                    Text(verbatim: website).vaultType(.footnote).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(verbatim: link.address).vaultType(.footnote).themedForeground(.secondaryBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(minHeight: Metric.hitMin, alignment: .leading)
    }
}

struct AliasLinkedServiceDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let link: AliasLinkedService
    @State private var confirmingUnlink = false
    @State private var errorMessage: String?

    /// Keep the original confirmation snapshot. A changed live relation must
    /// require reopening/reconfirming instead of broadening the user's action.
    private var alias: EmailAlias? {
        env.repository.aliases.first { $0.id == link.aliasID && $0.personaId == link.personaID }
    }
    private var login: VaultItem? {
        guard let persona = env.repository.personas.first(where: { $0.id == link.personaID }),
              env.repository.activePersona?.id == persona.id else { return nil }
        return env.repository.items(for: persona).first { $0.id == link.itemID }
    }

    var body: some View {
        List {
            Section {
                Text(verbatim: link.itemTitle).vaultType(.headline).themedForeground()
                    .fixedSize(horizontal: false, vertical: true)
                if let website = link.website {
                    PrivateEmailFieldValue(label: "Website", value: website)
                }
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Private email").vaultType(.footnote).themedForeground(.secondaryBody)
                    Text(verbatim: link.address).vaultType(.body).themedForeground()
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                if let target = alias?.forwardingTarget {
                    PrivateEmailFieldValue(label: "Forwards to", value: EmailMask.masked(target))
                }
            }.listRowBackground(VaultColors.surface)
            Section {
                if alias != nil {
                    NavigationLink { AliasDetailScreen(aliasID: link.aliasID) } label: {
                        Label { Text("Manage private email") } icon: { VaultIcon(Icons.mail) }
                            .frame(minHeight: Metric.hitMin)
                    }
                }
                if login != nil {
                    NavigationLink { ItemDetailScreen(itemID: link.itemID) } label: {
                        Label { Text("Open login") } icon: { VaultIcon(Icons.key) }
                            .frame(minHeight: Metric.hitMin)
                    }
                }
            } footer: {
                Text("Unlinking keeps this address receiving mail. Manage forwarding in Private Email.").themedForeground(.secondaryBody)
            }.listRowBackground(VaultColors.surface)
        }
        .navigationTitle(Text("Linked service"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .themedFormBackground()
        .toolbar {
            ToolbarItem(placement: .platformPrimaryAction) {
                Menu {
                    Button(role: .destructive) { confirmingUnlink = true } label: {
                        Label { Text("Unlink") } icon: { VaultIcon(Icons.closeCircle) }
                    }.disabled(login == nil || alias == nil)
                } label: {
                    VaultIcon(Icons.moreHorizontal, size: Metric.iconUtility)
                        .themedForeground(.iconPrimary)
                        .frame(width: Metric.hitMin, height: Metric.hitMin)
                }.accessibilityLabel(Text("Manage linked service"))
            }
        }
        .confirmationDialog("Unlink this service?", isPresented: $confirmingUnlink, titleVisibility: .visible) {
            Button("Unlink", role: .destructive) {
                do { try env.repository.unlinkAliasFromLogin(link); Haptics.error(); dismiss() }
                catch let failure as VaultRepository.AliasLinkFailure { errorMessage = failure.userMessage; Haptics.error() }
                catch { errorMessage = appString("Your changes are still here. Try saving again."); Haptics.error() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the private email from this vault item. Forwarding and the service account stay unchanged.")
        }
        .alert("Couldn’t update the link", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: errorMessage ?? "") }
        .onChange(of: env.repository.activePersona?.id) { _, id in if id != link.personaID { dismiss() } }
    }
}

private struct AliasLegacyReviewSheet: View {
    @Environment(AppEnvironment.self) private var env
    let personaID: String
    let aliasID: String?
    @State private var candidate: AliasLinkedService?
    @State private var errorMessage: String?
    private var candidates: [AliasLinkedService] {
        env.repository.legacyAliasCandidates(for: personaID, aliasID: aliasID)
    }
    var body: some View {
        VaultSheetScaffold(title: "Review saved logins", leading: { EmptyView() },
                           trailing: { SheetDismissButton("Done") }) {
            List {
                Section {
                    if candidates.isEmpty {
                        Text("No matching saved logins").themedForeground(.secondaryBody)
                    }
                    ForEach(candidates) { link in
                        Button { candidate = link } label: { AliasLinkedServiceRow(link: link) }
                    }
                } footer: {
                    Text("Linking adds a separate Private email field. Your existing email and username stay unchanged.").themedForeground(.secondaryBody)
                }.listRowBackground(VaultColors.surface)
            }.themedFormBackground()
        }
        .confirmationDialog("Link this login?", isPresented: Binding(
            get: { candidate != nil }, set: { if !$0 { candidate = nil } }), titleVisibility: .visible) {
            Button("Link") {
                guard let selected = candidate else { return }
                do {
                    try env.repository.linkAliasToLogin(aliasID: selected.aliasID, itemID: selected.itemID,
                        expectedItemUpdatedAt: selected.itemUpdatedAt, expectedAliasRevision: selected.aliasRelationRevision)
                    Haptics.success()
                } catch let failure as VaultRepository.AliasLinkFailure { errorMessage = failure.userMessage }
                catch { errorMessage = appString("Your changes are still here. Try saving again.") }
                candidate = nil
            }
            Button("Cancel", role: .cancel) { candidate = nil }
        } message: {
            Text("Linking adds a separate Private email field. Your existing email and username stay unchanged.").themedForeground(.secondaryBody)
        }
        .alert("Couldn’t update the link", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: errorMessage ?? "") }
    }
}

/// Dedicated local linking is available even when the relay is offline/off.
struct AliasLoginPickerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let aliasID: String
    @State private var editorTarget: EditorTarget?
    @State private var errorMessage: String?
    @State private var repairLoginID: String?
    @State private var showingRepairLogin = false
    private var alias: EmailAlias? { env.repository.aliases.first { $0.id == aliasID } }
    private var persona: Persona? {
        alias.flatMap { alias in env.repository.personas.first { $0.id == alias.personaId && $0.id == env.repository.activePersona?.id } }
    }
    private var logins: [VaultItem] {
        persona.map { env.repository.items(for: $0).filter { $0.category == .login && !$0.isUnsupportedSchema } } ?? []
    }

    var body: some View {
        VaultSheetScaffold(title: "Link a login", leading: { EmptyView() }, trailing: { SheetDismissButton("Done") }) {
            List {
                Section {
                    Button { createLogin() } label: {
                        Label { Text("Create login") } icon: { VaultIcon(Icons.addCircle) }
                            .frame(minHeight: Metric.hitMin)
                    }.disabled(alias?.resolvedAddress == nil || persona == nil)
                }.listRowBackground(VaultColors.surface)
                Section {
                    if logins.isEmpty { Text("No saved logins yet").themedForeground(.secondaryBody) }
                    ForEach(logins) { login in
                        Button { link(login) } label: {
                            VStack(alignment: .leading, spacing: Space.s1) {
                                Text(verbatim: login.title).vaultType(.body).themedForeground()
                                if let host = login.autofillHost {
                                    Text(verbatim: host).vaultType(.footnote).themedForeground(.secondaryBody)
                                }
                            }.frame(minHeight: Metric.hitMin, alignment: .leading)
                        }
                    }
                } header: { Text("Saved logins") } footer: {
                    Text("Linking adds a separate Private email field. Your existing email and username stay unchanged.").themedForeground(.secondaryBody)
                }.listRowBackground(VaultColors.surface)
            }.themedFormBackground()
        }
        .sheet(item: $editorTarget) { target in ItemEditorScreen(target: target) }
        .sheet(isPresented: $showingRepairLogin) {
            if let id = repairLoginID {
                NavigationStack {
                    ItemDetailScreen(itemID: id)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { SheetDismissButton("Done") } }
                }.themedColorScheme()
            }
        }
        .alert("Couldn’t update the link", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            if repairLoginID != nil {
                Button("Open login") { showingRepairLogin = true }
            }
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: errorMessage ?? "") }
    }

    private func link(_ login: VaultItem) {
        guard let alias else { return }
        repairLoginID = login.id
        do {
            try env.repository.linkAliasToLogin(aliasID: alias.id, itemID: login.id,
                expectedItemUpdatedAt: login.updatedAt, expectedAliasRevision: alias.relationRevision)
            Haptics.success()
            dismiss()
        } catch let failure as VaultRepository.AliasLinkFailure { errorMessage = failure.userMessage; Haptics.error() }
        catch { errorMessage = appString("Your changes are still here. Try saving again."); Haptics.error() }
    }

    private func createLogin() {
        guard let alias, let persona, let address = alias.resolvedAddress else { return }
        repairLoginID = nil
        var draft = VaultItem(category: .login, title: alias.label ?? alias.boundDomain ?? "",
            folderId: persona.primarySpaceID, fields: ItemCategory.login.fieldTemplate)
        if let website = alias.boundDomain, let index = draft.fields.firstIndex(where: { $0.kind == .url }) {
            draft.fields[index].value = website
        }
        do {
            draft = try AliasWriteback.linking(draft, address: address)
            editorTarget = .aliasLogin(draft, aliasID: alias.id, personaID: persona.id,
                                       relationRevision: alias.relationRevision)
        } catch let failure as AliasWriteback.Failure { errorMessage = VaultRepository.AliasLinkFailure.field(failure).userMessage }
        catch { errorMessage = appString("Couldn’t update the link") }
    }
}
