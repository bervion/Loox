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
    @State private var errorTitle = ""
    @State private var errorMessage: String?
    @State private var errorOffersReset = false
    @State private var pendingDeleteInbox: ForwardingInbox?
    @State private var verificationScope: UUID?
    private var verification: ForwardingInboxVerification { env.destinationVerification.verification }

    private var visibleInboxes: [ForwardingInbox] {
        env.repository.forwardingInboxes.filter {
            $0.source == .manual || $0.personaId == env.repository.activePersona?.id
        }
    }

    private var gate: PrivateEmailGate { PrivateEmailGate(env) }

    var body: some View {
        List {
            // Same capability state, same explanation as the Private Email root
            // one level up. Saved inboxes below stay visible and manageable in
            // every state — only the relay-touching actions gate.
            PrivateEmailBannerSection()

            Section {
                ForEach(visibleInboxes) { inbox in
                    inboxRow(inbox)
                }
                if gate.allows(.create) {
                    Button { addingInbox = true } label: {
                        Label { Text("Add inbox") } icon: { VaultIcon(Icons.addCircle) }
                    }
                }
            } footer: {
                Text("New addresses will forward here. Existing addresses keep their inbox until you update them.").themedForeground(.secondaryBody)
            }
            .listRowBackground(VaultColors.surface)

            pendingSection
        }
        .navigationTitle(Text("Forwarding inboxes"))
        .alert("Add inbox", isPresented: $addingInbox) {
            TextField("Email", text: $newEmail)
                .platformKeyboardType(.emailAddress).platformAutocapitalization(.never)
            TextField("Label", text: $newLabel)
            Button("Cancel", role: .cancel) { newEmail = ""; newLabel = "" }
            Button("Save") { addInbox() }
        } message: {
            Text("A real inbox your private addresses can forward to.")
        }
        .relayFailureAlert(title: errorTitle, message: errorMessage, isPresented: errorBinding,
                           offersReset: errorOffersReset) { resetPrivateEmail() }
        // Verification reports through its own controller — success included, so
        // a sent email is confirmed on screen and not just in the user's inbox.
        .relayOutcomeAlert(verification, relay: env.relay)
        .confirmationDialog("Delete this inbox?", isPresented: deleteInboxBinding,
                            titleVisibility: .visible, presenting: pendingDeleteInbox) { inbox in
            Button("Delete", role: .destructive) {
                Haptics.error()
                try? env.repository.deleteInbox(inbox)
            }
        } message: { _ in
            Text("You can add it again later if you need to.")
        }
        .onAppear {
            verificationScope = env.destinationVerification.register(Set(visibleInboxes.map(\.id)))
        }
        .onChange(of: visibleInboxes.map(\.id)) { _, ids in
            if let verificationScope { env.destinationVerification.update(verificationScope, inboxIDs: Set(ids)) }
        }
        .onDisappear {
            if let verificationScope { env.destinationVerification.unregister(verificationScope) }
            verificationScope = nil
        }
    }

    /// Rotation drift surface: shows only when some addresses still forward to
    /// an inbox that is no longer their resolved destination.
    @ViewBuilder private var pendingSection: some View {
        let pending = env.repository.aliasesNeedingRotation.count
        // The update itself is a relay round trip per address, so the OFFER
        // hides while the relay can't be reached or the feature is off; the
        // drift is still there when it comes back. A run already in flight
        // keeps its progress row whatever the gate does mid-run.
        if rotating || (gate.allows(.mutate) && pending > 0) {
            Section {
                if rotating {
                    HStack(spacing: Space.s3) {
                        ProgressView()
                        Text("\(rotationDone) of \(rotationTotal)")
                            .vaultType(.subhead).themedForeground(.secondaryBody)
                    }
                } else {
                    Button { reconcile() } label: {
                        Label { Text("Update existing addresses") } icon: { VaultIcon(Icons.refresh) }
                    }
                }
            } footer: {
                Text("Keep Loox open until the update finishes. You can safely retry; finished addresses aren’t repeated.").themedForeground(.secondaryBody)
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    private func inboxRow(_ inbox: ForwardingInbox) -> some View {
        // Tap opens the detail screen — activate/default/delete were reachable
        // only through a long-press context menu, which nothing advertised.
        // The context menu and swipe stay as shortcuts.
        NavigationLink { ForwardingInboxDetailScreen(inboxID: inbox.id) } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text(verbatim: EmailMask.masked(inbox.email))
                    .vaultType(.body).themedForeground(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: subtitle(inbox))
                    .vaultType(.caption).themedForeground(.secondaryBody)
                HStack(spacing: Space.s3) {
                    verificationChip(inbox)
                    if inbox.isDefault {
                        Text("Default").vaultType(.caption).themedForeground(.accentText)
                    }
                }
            }
            .padding(.vertical, Space.s1)
        }
        .contentShape(Rectangle())
        .contextMenu {
            verificationMenuItems(inbox)
            if !inbox.isDefault {
                Button { try? env.repository.setDefaultInbox(inbox) } label: {
                    Label { Text("Set as default") } icon: { VaultIcon(Icons.checkCircle) }
                }
            }
            if inbox.source == .manual {
                Button(role: .destructive) { pendingDeleteInbox = inbox } label: {
                    Label { Text("Delete") } icon: { VaultIcon(Icons.trash) }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if inbox.source == .manual {
                Button(role: .destructive) { pendingDeleteInbox = inbox } label: {
                    Label { Text("Delete") } icon: { VaultIcon(Icons.trash) }
                }
            }
        }
    }

    /// Ownership-verification badge (DEC-DST-01). Muted while unverified so it
    /// reads as "action available", not "error" — forwarding still works until
    /// the server enforces verification.
    @ViewBuilder private func verificationChip(_ inbox: ForwardingInbox) -> some View {
        switch inbox.verificationStatus {
        case .verified:
            Text("Verified").vaultType(.caption).themedForeground(.successBody)
        case .pending:
            Text("Awaiting confirmation").vaultType(.caption).themedForeground(.warningBody)
        case .unverified, .revoked:
            Text("Not verified").vaultType(.caption).themedForeground(.secondaryBody)
        }
    }

    /// Verification is a signed relay command, so the offer follows the gate —
    /// the badge above keeps reporting the last known status either way. A menu
    /// item cannot show progress, so both actions are disabled while one is in
    /// flight and the send is withheld for as long as the relay asked; the
    /// detail screen behind the row is where the state is legible.
    @ViewBuilder private func verificationMenuItems(_ inbox: ForwardingInbox) -> some View {
        if gate.allows(.mutate) || env.capabilities.canRefreshDestinationStatus {
            let waiting = verification.resendWait(for: inbox)
            switch inbox.verificationStatus {
            case .verified:
                EmptyView()
            case .pending:
                Button {
                    Task { await verification.check(inbox, relay: env.relay) }
                } label: {
                    Label { Text("Check verification") } icon: { VaultIcon(Icons.checkCircle) }
                }
                .disabled(verification.isBusy(inbox) || !env.capabilities.canRefreshDestinationStatus)
                if gate.allows(.mutate) {
                    resendButton(inbox, title: "Resend email", icon: Icons.refresh, waiting: waiting)
                }
            case .unverified, .revoked:
                if gate.allows(.mutate) {
                    resendButton(inbox, title: "Confirm email", icon: Icons.checkCircle, waiting: waiting)
                }
            }
        }
    }

    /// Begin/resend verification: signs a kind-7 command over the exact email;
    /// the backend sends the confirm link. The user confirms on the web; we only
    /// poll the result (never self-confirm). Each tap is one more email in
    /// someone's inbox, so the controller — not this button — decides whether a
    /// send may happen at all.
    @ViewBuilder
    private func resendButton(_ inbox: ForwardingInbox, title: LocalizedStringKey,
                              icon: String, waiting: Int) -> some View {
        Button {
            Task { await verification.send(to: inbox, relay: env.relay) }
        } label: {
            // During the cooldown the row states the wait rather than
            // disappearing: an item that vanishes reads as a broken menu, and
            // the countdown is the answer to "why can't I send again".
            if waiting > 0 {
                Label { Text(verbatim: appString("Send again in \(waiting)s")) }
                    icon: { VaultIcon(Icons.clock) }
            } else {
                Label { Text(title) } icon: { VaultIcon(icon) }
            }
        }
        .disabled(waiting > 0 || verification.isBusy(inbox))
    }

    private func subtitle(_ inbox: ForwardingInbox) -> String {
        if let label = inbox.label, !label.isEmpty { return label }
        if inbox.source == .personaProfile {
            let persona = env.repository.personas.first { $0.id == inbox.personaId }
            return persona.map { "\(appString("Profile email")) (\($0.displayName))" }
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
            } catch let failure as RelayService.Failure {
                // Finished aliases are checkpointed — the section re-offers the rest.
                errorTitle = failure.userTitle
                errorMessage = failure.userMessage
                errorOffersReset = failure.offersPrivateEmailReset
                Haptics.error()
            } catch {
                errorTitle = appString("Couldn’t reach the relay")
                errorMessage = appString("Check your connection and iCloud, then try again.")
                Haptics.error()
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil; errorOffersReset = false } })
    }

    /// The failure alert's deliberate recovery: reset Private Email when this
    /// vault can't open its key, then report the result in the same alert.
    private func resetPrivateEmail() {
        Task {
            let result = await PrivateEmailReset.run(using: env.relay)
            errorOffersReset = result.offersReset
            errorTitle = result.title
            errorMessage = result.message
        }
    }

    private var deleteInboxBinding: Binding<Bool> {
        Binding(get: { pendingDeleteInbox != nil }, set: { if !$0 { pendingDeleteInbox = nil } })
    }
}
