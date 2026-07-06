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
    @State private var editingDestination = false
    @State private var destinationDraft = ""

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
        .navigationTitle(Text("Alias"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .alert(Text("Couldn’t reach the relay"), isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: errorMessage ?? "") }
    }

    @ViewBuilder private func content(_ alias: EmailAlias) -> some View {
        let address = AliasAddress.display(localPart: alias.localPart, status: alias.status,
                                           relayDomain: RelayConfig.emailDomain)
        List {
            Section("Address") {
                Button {
                    env.clipboard.copy(address, label: appString("Email aliases"), sensitive: false)
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
            }
            .listRowBackground(VaultColors.surface)

            Section {
                LabeledContent { Text(verbatim: alias.forwardingTarget ?? "—") } label: { Text("Forwards to") }
                Button {
                    destinationDraft = alias.forwardingTarget ?? (persona.flatMap { env.repository.destinationEmail(for: $0) } ?? "")
                    editingDestination = true
                } label: { Text("Change forwarding address") }
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
                    Button(role: .destructive) { run { try await env.relay.disable(alias) } } label: {
                        Label { Text("Disable") } icon: { PolarisIcon(Icons.hide) }
                    }
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label { Text("Delete") } icon: { PolarisIcon(Icons.trash) }
                }
            }
            .listRowBackground(VaultColors.surface)
        }
        .disabled(busy)
        .alert("Change forwarding address", isPresented: $editingDestination) {
            TextField("Email", text: $destinationDraft)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never)
            Button("Cancel", role: .cancel) {}
            Button("Save") { changeDestination() }
        } message: {
            Text("Mail to your aliases will forward here. Changing it re-points every alias of this identity.")
        }
        .confirmationDialog("Delete this alias?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { run { try await env.relay.delete(alias) } }
        } message: {
            Text("The address stops working immediately and cannot be restored.")
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
            catch { errorMessage = appString("Check your connection and iCloud, then try again.") }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
