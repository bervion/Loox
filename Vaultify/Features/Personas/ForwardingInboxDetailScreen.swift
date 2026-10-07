import SwiftUI

/// A deliberate, unlocked detail visit can identify the local recipient in
/// full. Disclosure is ephemeral: inactive, lock and exit conceal immediately;
/// foreground never reveals it again. Overview remains masked.
struct ForwardingInboxDetailScreen: View {
    let inboxID: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmDelete = false
    @State private var revealed = false
    @State private var initialDisclosureHandled = false
    @State private var verificationScope: UUID?

    private var inbox: ForwardingInbox? { env.repository.inbox(id: inboxID) }
    private var gate: PrivateEmailGate { PrivateEmailGate(env) }
    private var verification: ForwardingInboxVerification { env.destinationVerification.verification }
    private var canReveal: Bool { env.session.state == .unlocked && scenePhase == .active }

    var body: some View {
        List {
            if let inbox {
                identitySection(inbox)
                verificationSection(inbox)
                routingSection(inbox)
                if !inbox.isDefault {
                    Section {
                        Button { try? env.repository.setDefaultInbox(inbox) } label: {
                            Label { Text("Set as default") } icon: { VaultIcon(Icons.checkCircle) }
                        }
                        .frame(minHeight: Metric.hitMin)
                    } footer: { Text("New addresses forward here. Existing addresses keep their current inbox.").themedForeground(.secondaryBody) }
                    .listRowBackground(VaultColors.surface)
                }
            } else {
                Section { Text("This inbox is no longer in your vault.").themedForeground(.secondaryBody) }
                    .listRowBackground(VaultColors.surface)
            }
            PrivateEmailBannerSection()
        }
        .navigationTitle(Text("Inbox"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            if inbox?.source == .manual {
                ToolbarItem(placement: .platformPrimaryAction) {
                    Menu {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label { Text("Delete inbox") } icon: { VaultIcon(Icons.trash) }
                        }
                        .disabled(env.repository.aliases.contains { $0.forwardingInboxID == inboxID })
                    } label: { VaultIcon(Icons.moreHorizontal) }
                    .accessibilityLabel(Text("Inbox actions"))
                }
            }
        }
        .relayOutcomeAlert(verification, relay: env.relay)
        .confirmationDialog("Delete this inbox?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Haptics.error()
                if let inbox { try? env.repository.deleteInbox(inbox) }
                dismiss()
            }
        } message: { Text("You can add it again later if you need to.") }
        .onAppear {
            if !initialDisclosureHandled {
                revealed = canReveal
                initialDisclosureHandled = true
            }
            verificationScope = env.destinationVerification.register([inboxID], priority: true)
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { revealed = false } }
        .onChange(of: env.session.state) { _, state in if state != .unlocked { revealed = false } }
        .onChange(of: inbox?.email) { _, _ in revealed = false }
        .onDisappear {
            revealed = false
            if let verificationScope { env.destinationVerification.unregister(verificationScope) }
            verificationScope = nil
        }
    }

    private func identitySection(_ inbox: ForwardingInbox) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Space.s3) {
                if let label = inbox.label, !label.isEmpty {
                    Text(verbatim: label).vaultType(.headline).themedForeground(.primary)
                }
                Text(verbatim: revealed && canReveal ? inbox.email : EmailMask.masked(inbox.email))
                    .vaultType(.body).themedForeground(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                statusLabel(inbox)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Space.s1) { disclosureButton; copyButton(inbox) }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Space.s3) { disclosureButton; copyButton(inbox) }
                        VStack(alignment: .leading, spacing: Space.s1) { disclosureButton; copyButton(inbox) }
                    }
                }
            }
            .padding(.vertical, Space.s2)
            if inbox.isDefault {
                Label { Text("Default for new addresses").vaultType(.subhead) }
                    icon: { VaultIcon(Icons.checkCircle).themedForeground(.accentText) }
            }
        } footer: { Text("A real inbox your private addresses can forward to.").themedForeground(.secondaryBody) }
        .listRowBackground(VaultColors.surface)
    }

    private var disclosureButton: some View {
        Button {
            if revealed { revealed = false }
            else if canReveal { withAnimation(.vault(Motion.standard, reduceMotion: reduceMotion)) { revealed = true } }
            Haptics.tap()
        } label: {
            Label {
                Text(verbatim: revealed ? appString("Hide email") : appString("Show email"))
                    .vaultType(.subhead).fixedSize(horizontal: false, vertical: true)
            }
                icon: { VaultIcon(revealed ? Icons.hide : Icons.reveal) }
                .frame(minHeight: Metric.hitMin)
        }
        .buttonStyle(.borderless)
        .disabled(!canReveal)
    }
    private func copyButton(_ inbox: ForwardingInbox) -> some View {
        Button {
            guard canReveal, revealed, env.repository.inbox(id: inbox.id)?.email == inbox.email else { return }
            env.clipboard.copy(inbox.email, label: appString("Email"), sensitive: true)
        } label: {
            Label { Text("Copy email").vaultType(.subhead).fixedSize(horizontal: false, vertical: true) }
                icon: { VaultIcon(Icons.copy) }
                .frame(minHeight: Metric.hitMin)
        }
        .buttonStyle(.borderless)
        .disabled(!revealed || !canReveal)
    }

    @ViewBuilder private func verificationSection(_ inbox: ForwardingInbox) -> some View {
        if inbox.verificationStatus != .verified {
            Section {
                if inbox.verificationStatus == .pending {
                    Text("Open the confirmation link in your inbox, then return here.")
                        .vaultType(.subhead).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                    actionButton(inbox, title: "Check verification", activity: .checking) {
                        await verification.check(inbox, relay: env.relay)
                    }
                    .disabled(!env.capabilities.canRefreshDestinationStatus || verification.isBusy(inbox))
                    if gate.allows(.mutate) { resendRow(inbox, title: "Resend email") }
                } else if gate.allows(.mutate) {
                    actionButton(inbox, title: "Send confirmation email", activity: .sending) {
                        await verification.send(to: inbox, relay: env.relay)
                    }
                    .disabled(!verification.canSend(to: inbox))
                }
                if let error = env.destinationVerification.errors[inbox.id] {
                    Text(verbatim: error).vaultType(.footnote).themedForeground(.secondaryBody)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(VaultColors.surface)
        }
    }
    private func actionButton(_ inbox: ForwardingInbox, title: LocalizedStringKey,
                              activity: ForwardingInboxVerification.Activity,
                              action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Text(title).frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                .prominentButtonLoading(verification.isBusy(inbox) && verification.activity == activity,
                                        tint: Color.platformBackground)
        }
        .buttonStyle(.themedProminent)
    }
    @ViewBuilder private func resendRow(_ inbox: ForwardingInbox, title: LocalizedStringKey) -> some View {
        let wait = verification.resendWait(for: inbox)
        if wait > 0 {
            Text(verbatim: appString("You can send again in \(wait)s"))
                .vaultType(.footnote).themedForeground(.secondaryBody)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button { Task { await verification.send(to: inbox, relay: env.relay) } } label: {
                Text(title).vaultType(.subhead).frame(minHeight: Metric.hitMin)
            }
            .disabled(verification.isBusy(inbox))
        }
    }
    @ViewBuilder private func routingSection(_ inbox: ForwardingInbox) -> some View {
        let aliases = env.repository.activePersona.map { env.repository.aliases(forPersona: $0.id) } ?? []
        let actual = aliases.filter { $0.backendMinted && $0.forwardingTarget == inbox.email && $0.status != .disabled }
        let waiting = aliases.filter {
            $0.backendMinted && $0.status != .disabled && env.repository.resolvedDestination(for: $0) == inbox.email && $0.forwardingTarget != inbox.email
        }
        if !actual.isEmpty || !waiting.isEmpty {
            Section {
                ForEach(actual) { alias in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(verbatim: alias.label ?? alias.localPart).vaultType(.body).themedForeground(.primary)
                        Text(alias.status == .active ? "Forwarding here" : "Forwarding paused")
                            .vaultType(.caption)
                            .themedForeground(alias.status == .active ? .successBody : .secondaryBody)
                    }
                }
                ForEach(waiting) { alias in
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(verbatim: alias.label ?? alias.localPart).vaultType(.body).themedForeground(.primary)
                        Text("Update pending").vaultType(.caption).themedForeground(.warningBody)
                    }
                }
            } header: { Text("Private addresses") }
            .listRowBackground(VaultColors.surface)
        }
    }
    @ViewBuilder private func statusLabel(_ inbox: ForwardingInbox) -> some View {
        switch inbox.verificationStatus {
        case .verified:
            Label { Text("Verified").vaultType(.subhead).themedForeground(.successBody) }
                icon: { VaultIcon(Icons.checkCircle).themedForeground(.successBody) }
        case .pending:
            Label { Text("Awaiting confirmation").vaultType(.subhead).themedForeground(.warningBody) }
                icon: { VaultIcon(Icons.clock).themedForeground(.warningBody) }
        case .unverified, .revoked:
            Label { Text("Not verified").vaultType(.subhead).themedForeground(.secondaryBody) }
                icon: { VaultIcon(Icons.mail).themedForeground(.secondaryBody) }
        }
    }
}
