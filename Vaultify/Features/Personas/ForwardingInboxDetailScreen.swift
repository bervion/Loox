import SwiftUI

/// Detail for one forwarding inbox: identity (masked email, label, source),
/// verification status, and every action as a VISIBLE row — the list screen
/// previously hid activate/default/delete behind a long-press context menu,
/// which nothing advertised. The context menu stays for power users; this is
/// the discoverable path.
struct ForwardingInboxDetailScreen: View {
    let inboxID: String

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    private var inbox: ForwardingInbox? {
        env.repository.forwardingInboxes.first { $0.id == inboxID }
    }

    var body: some View {
        List {
            if let inbox {
                identitySection(inbox)
                actionsSection(inbox)
                if inbox.source == .manual {
                    deleteSection(inbox)
                }
            }
        }
        .navigationTitle(Text("Inbox"))
        .alert(Text("Couldn’t reach the relay"), isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: errorMessage ?? "") }
        .confirmationDialog("Delete this inbox?", isPresented: $confirmDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Haptics.error()
                if let inbox { try? env.repository.deleteInbox(inbox) }
                dismiss()
            }
        } message: {
            Text("You can add it again later if you need to.")
        }
    }

    @ViewBuilder private func identitySection(_ inbox: ForwardingInbox) -> some View {
        Section {
            LabeledContent { Text(verbatim: EmailMask.masked(inbox.email)) }
                label: { Text("Email") }
            if let label = inbox.label, !label.isEmpty {
                LabeledContent { Text(verbatim: label) } label: { Text("Label") }
            }
            LabeledContent { statusText(inbox) } label: { Text("Status") }
            if inbox.isDefault {
                LabeledContent { Text("New addresses forward here") }
                    label: { Text("Default") }
            }
        } footer: {
            Text("A real inbox your private addresses can forward to.")
        }
        .listRowBackground(VaultColors.surface)
    }

    @ViewBuilder private func actionsSection(_ inbox: ForwardingInbox) -> some View {
        Section {
            switch inbox.verificationStatus {
            case .verified:
                EmptyView()
            case .pending:
                Button { checkVerification(inbox) } label: {
                    Label { Text("Check verification") } icon: { PolarisIcon(Icons.checkCircle) }
                }
                Button { confirmEmail(inbox) } label: {
                    Label { Text("Resend email") } icon: { PolarisIcon("ic_refresh") }
                }
            case .unverified, .revoked:
                Button { confirmEmail(inbox) } label: {
                    Label { Text("Confirm email") } icon: { PolarisIcon(Icons.checkCircle) }
                }
            }
            if !inbox.isDefault {
                Button { try? env.repository.setDefaultInbox(inbox) } label: {
                    Label { Text("Set as default") } icon: { PolarisIcon(Icons.checkCircle) }
                }
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    @ViewBuilder private func deleteSection(_ inbox: ForwardingInbox) -> some View {
        Section {
            Button(role: .destructive) { confirmDelete = true } label: {
                Label { Text("Delete").foregroundStyle(env.theme.active.color(.destructive)) }
                    icon: { PolarisIcon(Icons.trash).foregroundStyle(env.theme.active.color(.destructive)) }
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    /// Muted while unverified so it reads as "action available", not "error" —
    /// forwarding still works until the server enforces verification.
    @ViewBuilder private func statusText(_ inbox: ForwardingInbox) -> some View {
        switch inbox.verificationStatus {
        case .verified:
            Text("Verified").themedForeground(.success)
        case .pending:
            Text("Awaiting confirmation").themedForeground(.warning)
        case .unverified, .revoked:
            Text("Not verified").themedForeground(.secondary)
        }
    }

    private func confirmEmail(_ inbox: ForwardingInbox) {
        Task {
            do { _ = try await env.relay.beginDestinationVerification(inbox) }
            catch let failure as RelayService.Failure {
                errorMessage = failure.userMessage
                Haptics.error()
            } catch {
                errorMessage = appString("Check your connection and iCloud, then try again.")
                Haptics.error()
            }
        }
    }

    private func checkVerification(_ inbox: ForwardingInbox) {
        Task {
            do { _ = try await env.relay.refreshDestinationStatus(inbox) }
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
