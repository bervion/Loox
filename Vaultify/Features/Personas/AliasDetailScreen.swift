import SwiftUI

/// Detail + management for one email alias: its address, what it forwards to
/// (editable → re-rotates on the backend), where it's bound, and the destructive
/// actions (disable, delete). Reads live from the repository so a status change
/// reflects immediately.
struct AliasDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let aliasID: String

    @State private var busy = false
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var confirmPause = false
    @State private var editingDestination = false
    @State private var destinationDraft = ""
    @State private var editingLabel = false
    @State private var labelDraft = ""

    /// Live alias (nil once deleted — the screen then pops).
    private var alias: EmailAlias? { env.repository.aliases.first { $0.id == aliasID } }
    private var persona: Persona? {
        alias.flatMap { a in env.repository.personas.first { $0.id == a.personaId } }
    }

    var body: some View {
        Group {
            if let alias {
                content(alias)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .navigationTitle(Text("Private Email"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .alert(Text("Couldn’t reach the relay"), isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: errorMessage ?? "") }
    }

    @ViewBuilder private func content(_ alias: EmailAlias) -> some View {
        let address = AliasAddress.display(localPart: alias.localPart, status: alias.status,
                                           relayDomain: alias.emailDomain)
        List {
            Section("Address") {
                Button {
                    env.clipboard.copy(address, label: appString("Private Email"), sensitive: false)
                } label: {
                    HStack {
                        Text(verbatim: address).themedForeground(.primary)
                        Spacer()
                        PolarisIcon(Icons.copy, size: 16).themedForeground(.iconSecondary)
                    }
                }
                LabeledContent { Text(verbatim: statusLabel(alias.status)) } label: { Text("Status") }
                if let domain = alias.boundDomain, !domain.isEmpty {
                    LabeledContent { Text(verbatim: domain) } label: { Text("Website") }
                }
                Button {
                    labelDraft = alias.label ?? ""
                    editingLabel = true
                } label: {
                    LabeledContent { Text(verbatim: alias.label ?? appString("None")) } label: { Text("Label") }
                }
            }
            .listRowBackground(VaultColors.surface)

            Section {
                // Masked in overview; the full address appears only when editing.
                LabeledContent { Text(verbatim: alias.forwardingTarget.map(EmailMask.masked) ?? appString("None")) }
                    label: { Text("Forwards to") }
                // Per-alias inbox pin — offered once there's a choice to make.
                if env.repository.forwardingInboxes.count > 1 {
                    Menu {
                        ForEach(env.repository.forwardingInboxes) { inbox in
                            Button { pick(inbox, for: alias) } label: {
                                Text(verbatim: inboxTitle(inbox))
                            }
                        }
                    } label: {
                        LabeledContent { Text(verbatim: currentInboxTitle(alias)) }
                            label: { Text("Forwarding inbox") }
                    }
                }
                Button {
                    destinationDraft = alias.forwardingTarget ?? (persona.flatMap { env.repository.destinationEmail(for: $0) } ?? "")
                    editingDestination = true
                } label: { Text("Change forwarding address") }
                NavigationLink { ForwardingInboxScreen() } label: { Text("Forwarding inboxes") }
            } footer: {
                Text("Replies from your inbox may reveal your real email address.")
            }
            .listRowBackground(VaultColors.surface)

            Section {
                if alias.status == .reserved {
                    // Reserved means a prior activation didn't reach the relay — retry.
                    Button { run { try await env.relay.activate(alias) } } label: {
                        Label { Text("Activate") } icon: { PolarisIcon(Icons.checkCircle) }
                    }
                }
                if alias.status != .disabled {
                    // Pause is reversible later (relay keeps the row) — not destructive.
                    Button { confirmPause = true } label: {
                        Label { Text("Pause forwarding") } icon: { PolarisIcon(Icons.hide) }
                    }
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label { Text("Delete permanently") } icon: { PolarisIcon(Icons.trash) }
                }
            }
            .listRowBackground(VaultColors.surface)
        }
        .disabled(busy)
        .alert("Edit label", isPresented: $editingLabel) {
            TextField("Label", text: $labelDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveLabel(alias) }
        }
        .alert("Change forwarding address", isPresented: $editingDestination) {
            TextField("Email", text: $destinationDraft)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {}
            Button("Save") { changeDestination() }
        } message: {
            Text("Mail to your aliases will forward here. Changing it re-points every alias of this identity.")
        }
        .confirmationDialog("Pause forwarding?", isPresented: $confirmPause, titleVisibility: .visible) {
            Button("Pause forwarding") { Haptics.tap(); run { try await env.relay.disable(alias) } }
        } message: {
            Text("New messages sent to this address will no longer reach your inbox. You can turn forwarding back on later.")
        }
        .confirmationDialog("Delete this private address permanently?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete permanently", role: .destructive) {
                Haptics.error()
                run { try await env.relay.delete(alias) }
            }
        } message: {
            Text(verbatim: address + "\n")
                + Text("This address will stop forwarding and can never be restored or issued to anyone else. Accounts still using this address may no longer be able to send you password resets or important mail.")
        }
    }

    private func statusLabel(_ status: AliasStatus) -> String {
        switch status {
        case .active:   return appString("Forwarding active")
        case .reserved: return appString("Tap to activate")
        case .disabled: return appString("Forwarding paused")
        default:        return appString("Draft")
        }
    }

    private func inboxTitle(_ inbox: ForwardingInbox) -> String {
        if let label = inbox.label, !label.isEmpty { return label }
        return EmailMask.masked(inbox.email)
    }

    /// The inbox this alias currently resolves to (pin, else persona default).
    private func currentInboxTitle(_ alias: EmailAlias) -> String {
        if let id = alias.forwardingInboxID, let pinned = env.repository.inbox(id: id) {
            return inboxTitle(pinned)
        }
        if let persona, let fallback = env.repository.defaultInbox(for: persona) {
            return inboxTitle(fallback)
        }
        return appString("None")
    }

    private func pick(_ inbox: ForwardingInbox, for alias: EmailAlias) {
        run { try await env.relay.setInbox(inbox, for: alias) }
    }

    private func saveLabel(_ alias: EmailAlias) {
        var updated = alias
        let trimmed = labelDraft.trimmingCharacters(in: .whitespaces)
        updated.label = trimmed.isEmpty ? nil : trimmed
        try? env.repository.updateAlias(updated)
    }

    private func changeDestination() {
        let email = destinationDraft.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, let persona else { return }
        env.repository.setDestinationEmail(email, for: persona)   // update the real email
        run { try await env.relay.updateDestination(for: persona, to: email) }  // re-rotate aliases
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() }
            catch let failure as RelayService.Failure {
                errorMessage = failure.userMessage
                Haptics.error()
            } catch {
                errorMessage = appString("Check your connection and iCloud, then try again.")
                Haptics.error()
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
