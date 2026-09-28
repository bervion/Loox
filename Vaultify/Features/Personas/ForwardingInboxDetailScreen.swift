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
    @State private var verification = ForwardingInboxVerification()
    @State private var confirmDelete = false

    private var inbox: ForwardingInbox? {
        env.repository.forwardingInboxes.first { $0.id == inboxID }
    }
    private var gate: PrivateEmailGate { PrivateEmailGate(env) }

    var body: some View {
        List {
            // Inherits the parent's treatment: same banner, same explanation,
            // same way back to Settings. The inbox itself stays readable and
            // deletable in every state.
            PrivateEmailBannerSection()
            if let inbox {
                identitySection(inbox)
                actionsSection(inbox)
                if inbox.source == .manual {
                    deleteSection(inbox)
                }
            }
        }
        .navigationTitle(Text("Inbox"))
        // One surface for both answers: "we sent it" is as much a result as a
        // failure, and a send that reported nothing looked like a dead button.
        .relayOutcomeAlert(verification, relay: env.relay)
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

    /// Verification is a signed relay command, so the offer follows the gate
    /// while the status row above keeps reporting what we know. Setting the
    /// default is local and stays available. With neither on offer the section
    /// itself goes away rather than leaving an empty card.
    @ViewBuilder private func actionsSection(_ inbox: ForwardingInbox) -> some View {
        let offersVerification = gate.allows(.mutate) && inbox.verificationStatus != .verified
        if offersVerification || !inbox.isDefault {
            Section {
                if offersVerification {
                    switch inbox.verificationStatus {
                    case .verified:
                        EmptyView()
                    case .pending:
                        verificationRow(inbox, title: "Check verification",
                                        icon: Icons.checkCircle, activity: .checking) {
                            await verification.check(inbox, relay: env.relay)
                        }
                        resendRow(inbox, title: "Resend email")
                    case .unverified, .revoked:
                        resendRow(inbox, title: "Confirm email")
                    }
                }
                if !inbox.isDefault {
                    Button { try? env.repository.setDefaultInbox(inbox) } label: {
                        Label { Text("Set as default") } icon: { VaultIcon(Icons.checkCircle) }
                    }
                }
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    /// A verification action as a row that reports its own state: the glyph
    /// becomes a spinner while the call runs, and the row is inert until it
    /// finishes. Nothing here can be fired twice by an impatient second tap.
    private func verificationRow(_ inbox: ForwardingInbox, title: LocalizedStringKey,
                                 icon: String, activity: ForwardingInboxVerification.Activity,
                                 run: @escaping () async -> Void) -> some View {
        let busy = verification.isBusy(inbox) && verification.activity == activity
        return Button { Task { await run() } } label: {
            Label {
                Text(title)
            } icon: {
                if busy { ProgressView().controlSize(.small) } else { VaultIcon(icon) }
            }
        }
        .disabled(verification.isBusy(inbox))
    }

    /// Sending is the metered one: each tap puts another email in the user's
    /// inbox, so the row states how long the relay wants us to wait and refuses
    /// to send until then.
    @ViewBuilder private func resendRow(_ inbox: ForwardingInbox,
                                        title: LocalizedStringKey) -> some View {
        let wait = verification.resendWait(for: inbox)
        if wait > 0 {
            Label {
                Text(verbatim: appString("You can send again in \(wait)s"))
                    .themedForeground(.secondary)
            } icon: {
                VaultIcon(Icons.clock).themedForeground(.secondary)
            }
        } else {
            verificationRow(inbox, title: title, icon: Icons.refresh, activity: .sending) {
                await verification.send(to: inbox, relay: env.relay)
            }
        }
    }

    @ViewBuilder private func deleteSection(_ inbox: ForwardingInbox) -> some View {
        Section {
            Button(role: .destructive) { confirmDelete = true } label: {
                Label { Text("Delete").foregroundStyle(env.theme.active.color(.destructive)) }
                    icon: { VaultIcon(Icons.trash).foregroundStyle(env.theme.active.color(.destructive)) }
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
}
