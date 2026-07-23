import SwiftUI

/// Manage forwarding inboxes: where private-email addresses deliver. Derived
/// profile inboxes follow each identity's profile email; manual inboxes are
/// user-added. Changing the default affects NEW addresses only — existing
/// addresses keep their inbox until the user explicitly runs "Update existing
/// addresses" (resumable: re-runs finish exactly the stragglers).
struct ForwardingInboxScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    @State private var addingInbox = false
    @State private var newEmail = ""
    @State private var newLabel = ""
    @State private var rotating = false
    @State private var rotationDone = 0
    @State private var rotationTotal = 0
    @State private var errorMessage: String?
    @State private var pendingDeleteInbox: ForwardingInbox?

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
                .platformKeyboardType(.emailAddress).platformAutocapitalization(.never)
            TextField("Label", text: $newLabel)
            Button("Cancel", role: .cancel) { newEmail = ""; newLabel = "" }
            Button("Save") { addInbox() }
        } message: {
            Text("A real inbox your private addresses can forward to.")
        }
        .alert(Text("Couldn’t reach the relay"), isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: { Text(verbatim: errorMessage ?? "") }
        .confirmationDialog("Delete this inbox?", isPresented: deleteInboxBinding,
                            titleVisibility: .visible, presenting: pendingDeleteInbox) { inbox in
            Button("Delete", role: .destructive) {
                Haptics.error()
                try? env.repository.deleteInbox(inbox)
            }
        } message: { _ in
            Text("You can add it again later if you need to.")
        }
        // Auto-advance pending → verified: the user confirms on the web, so the
        // app must poll the result itself rather than wait for a manual tap.
        .task(id: scenePhase) { await pollPendingVerifications() }
    }

    /// Poll the read-only status endpoint (~8s) while any inbox is pending and
    /// the screen is active; stops when nothing is pending or the view goes away
    /// (the task is cancelled on disappear / scene change). A 404 is an id/config
    /// issue, not "pending", so it's swallowed here rather than resetting state.
    private func pollPendingVerifications() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            let pending = env.repository.forwardingInboxes.filter {
                $0.verificationStatus == .pending && $0.relayDestinationID != nil
            }
            guard !pending.isEmpty else { return }
            for inbox in pending { _ = try? await env.relay.refreshDestinationStatus(inbox) }
            try? await Task.sleep(for: .seconds(8))
        }
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
                Text("Keep Loox open until the update finishes. You can safely retry; finished addresses aren’t repeated.")
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    private func inboxRow(_ inbox: ForwardingInbox) -> some View {
        // Tap opens the detail screen — activate/default/delete were reachable
        // only through a long-press context menu, which nothing advertised.
        // The context menu and swipe stay as shortcuts.
        NavigationLink { ForwardingInboxDetailScreen(inboxID: inbox.id) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: EmailMask.masked(inbox.email))
                        .vaultType(.body).themedForeground(.primary)
                    Text(verbatim: subtitle(inbox))
                        .vaultType(.caption).themedForeground(.secondary)
                }
                Spacer()
                verificationChip(inbox)
                if inbox.isDefault {
                    Text("Default").vaultType(.caption).themedForeground(.accentText)
                }
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            verificationMenuItems(inbox)
            if !inbox.isDefault {
                Button { try? env.repository.setDefaultInbox(inbox) } label: {
                    Label { Text("Set as default") } icon: { PolarisIcon(Icons.checkCircle) }
                }
            }
            if inbox.source == .manual {
                Button(role: .destructive) { pendingDeleteInbox = inbox } label: {
                    Label { Text("Delete") } icon: { PolarisIcon(Icons.trash) }
                }
            }
        }
        .swipeActions(edge: .trailing) {
            if inbox.source == .manual {
                Button(role: .destructive) { pendingDeleteInbox = inbox } label: {
                    Label { Text("Delete") } icon: { PolarisIcon(Icons.trash) }
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
            Text("Verified").vaultType(.caption).themedForeground(.success)
        case .pending:
            Text("Awaiting confirmation").vaultType(.caption).themedForeground(.warning)
        case .unverified, .revoked:
            Text("Not verified").vaultType(.caption).themedForeground(.secondary)
        }
    }

    @ViewBuilder private func verificationMenuItems(_ inbox: ForwardingInbox) -> some View {
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
    }

    /// Begin/resend verification: signs a kind-7 command over the exact email;
    /// the backend sends the confirm link. The user confirms on the web; we only
    /// poll the result (never self-confirm).
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

    private var deleteInboxBinding: Binding<Bool> {
        Binding(get: { pendingDeleteInbox != nil }, set: { if !$0 { pendingDeleteInbox = nil } })
    }
}
