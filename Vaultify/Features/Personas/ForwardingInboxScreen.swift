import SwiftUI

/// Manage forwarding inboxes: where private-email addresses deliver. Derived
/// profile inboxes follow each identity's profile email; manual inboxes are
/// user-added. Changing the default affects NEW addresses only — existing
/// addresses keep their inbox until the user explicitly runs "Update existing
/// addresses" (resumable: re-runs finish exactly the stragglers).
struct ForwardingInboxScreen: View {
    @Environment(AppEnvironment.self) private var env

    @State private var addingInbox = false
    @State private var newEmail = ""
    @State private var newLabel = ""
    @State private var rotating = false
    @State private var rotationDone = 0
    @State private var rotationTotal = 0
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(env.repository.forwardingInboxes) { inbox in
                    inboxRow(inbox)
                }
                Button { addingInbox = true } label: {
                    Label { Text("Add inbox") } icon: { PolarisIcon(Icons.addCircle) }
                }
            } footer: {
                Text("New addresses will forward here. Existing addresses keep their inbox until you update them.")
            }
            .listRowBackground(VaultColors.surface)

            pendingSection
        }
        .navigationTitle(Text("Forwarding inboxes"))
        .alert("Add inbox", isPresented: $addingInbox) {
            TextField("Email", text: $newEmail)
                .keyboardType(.emailAddress).textInputAutocapitalization(.never)
            TextField("Label", text: $newLabel)
            Button("Cancel", role: .cancel) { newEmail = ""; newLabel = "" }
            Button("Save") { addInbox() }
        } message: {
            Text("A real inbox your private addresses can forward to.")
        }
        .alert(Text("Couldn’t reach the relay"), isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: errorMessage ?? "") }
    }

    /// Rotation drift surface: shows only when some addresses still forward to
    /// an inbox that is no longer their resolved destination.
    @ViewBuilder private var pendingSection: some View {
        let pending = env.repository.aliasesNeedingRotation.count
        if pending > 0 || rotating {
            Section {
                if rotating {
                    HStack(spacing: Space.s3) {
                        ProgressView()
                        Text("\(rotationDone) of \(rotationTotal)")
                            .vaultType(.subhead).themedForeground(.secondary)
                    }
                } else {
                    Button { reconcile() } label: {
                        Label { Text("Update existing addresses") } icon: { PolarisIcon("ic_refresh") }
                    }
                }
            } footer: {
                Text("Keep Loox open until the update finishes. You can safely retry — finished addresses aren’t repeated.")
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    private func inboxRow(_ inbox: ForwardingInbox) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: EmailMask.masked(inbox.email))
                    .vaultType(.body).themedForeground(.primary)
                Text(verbatim: subtitle(inbox))
                    .vaultType(.caption).themedForeground(.secondary)
            }
            Spacer()
            if inbox.isDefault {
                Text("Default").vaultType(.caption).themedForeground(.accent)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if !inbox.isDefault {
                Button { try? env.repository.setDefaultInbox(inbox) } label: {
                    Label { Text("Set as default") } icon: { PolarisIcon(Icons.checkCircle) }
                }
            }
            if inbox.source == .manual {
                Button(role: .destructive) { try? env.repository.deleteInbox(inbox) } label: {
                    Label { Text("Delete") } icon: { PolarisIcon(Icons.trash) }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if inbox.source == .manual {
                Button(role: .destructive) { try? env.repository.deleteInbox(inbox) } label: {
                    Label { Text("Delete") } icon: { PolarisIcon(Icons.trash) }
                }
            }
        }
    }

    private func subtitle(_ inbox: ForwardingInbox) -> String {
        if let label = inbox.label, !label.isEmpty { return label }
        if inbox.source == .personaProfile {
            let persona = env.repository.personas.first { $0.id == inbox.personaId }
            return persona.map { "\(appString("Profile email")) · \($0.displayName)" }
                ?? appString("Profile email")
        }
        return appString("Inbox")
    }

    private func addInbox() {
        let email = newEmail.trimmingCharacters(in: .whitespaces)
        defer { newEmail = ""; newLabel = "" }
        guard email.contains("@") else { return }
        let label = newLabel.trimmingCharacters(in: .whitespaces)
        _ = try? env.repository.addManualInbox(email: email, label: label.isEmpty ? nil : label)
    }

    private func reconcile() {
        rotating = true
        rotationDone = 0
        rotationTotal = env.repository.aliasesNeedingRotation.count
        Task {
            defer { rotating = false }
            do {
                try await env.relay.reconcileDestinations { done, total in
                    rotationDone = done
                    rotationTotal = total
                }
            } catch {
                // Finished aliases are checkpointed — the section re-offers the rest.
                errorMessage = appString("Check your connection and iCloud, then try again.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
