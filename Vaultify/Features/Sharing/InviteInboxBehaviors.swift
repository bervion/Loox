import SwiftUI

/// Recipient-side invite inbox (U5/U6), attached to the unlocked shell:
/// ONE reconcile path serves launch, foreground, push-hint, and re-unlock —
/// a missed push is never a lost invite, the public-db inbox is the truth.
/// Gated by `approvalModeEnabled` (a first-time recipient uses the link
/// tier, which is what turns the flag on) and by the vault being unlocked
/// (the participant identity lives under the Vault Key).
struct InviteInboxBehaviors: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    /// FIFO of discovered invites; an alert presents the head. Dedup across
    /// reconcile passes is the service's persisted seen-set.
    @State private var pendingInvites: [InviteEnvelope] = []
    @State private var reconciling = false
    @State private var acceptError: String?

    func body(content: Content) -> some View {
        content
            .task { await armAndReconcile() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await armAndReconcile() } }
            }
            // Push = wake-up hint only (U6); the reconcile query is the truth.
            .onReceive(NotificationCenter.default.publisher(for: .inviteRendezvousReceived)) { _ in
                Task { await armAndReconcile() }
            }
            .alert("Share invitation", isPresented: invitePresented) {
                Button("Not Now", role: .cancel) { advance() }
                Button("Accept") { acceptFirst() }
            } message: {
                Text("Someone shared an item with you in Loox Password. Accept to see it in \"Shared with Me\" on Home.")
            }
            .alert("Couldn't accept the invitation",
                   isPresented: Binding(get: { acceptError != nil },
                                        set: { if !$0 { acceptError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: acceptError ?? "")
            }
    }

    private var invitePresented: Binding<Bool> {
        Binding(get: { !pendingInvites.isEmpty && acceptError == nil },
                set: { if !$0 { } })  // dismissal handled by the buttons
    }

    private func advance() {
        if !pendingInvites.isEmpty { pendingInvites.removeFirst() }
    }

    private func acceptFirst() {
        guard let invite = pendingInvites.first else { return }
        Task {
            do {
                guard let url = URL(string: invite.shareURL) else {
                    throw InviteLinkService.Failure.malformedLink
                }
                try await env.inviteLinks.acceptShare(url: url)
                // Downstream is the standard acceptance resume: breadcrumb →
                // escrow/profile publish → the share appears in Shared with Me.
            } catch {
                acceptError = error.localizedDescription
            }
            advance()
        }
    }

    private func armAndReconcile() async {
        guard env.settings.approvalModeEnabled,
              let vaultKey = env.session.vaultKey?.bytes,
              !reconciling else { return }
        reconciling = true
        defer { reconciling = false }
        guard let identity = try? await env.participantEscrow.ensureIdentity(vaultKey: vaultKey)
        else { return }
        await env.inviteInbox.ensureArmed(identity: identity)
        let discovered = await env.inviteInbox.reconcile(identity: identity)
        guard !discovered.isEmpty else { return }
        let queued = Set(pendingInvites.map(\.inviteID))
        pendingInvites.append(contentsOf: discovered.filter { !queued.contains($0.inviteID) })
    }
}

extension View {
    /// Attach the recipient-side invite-inbox reconciler (see type docs).
    func inviteInboxBehaviors() -> some View { modifier(InviteInboxBehaviors()) }
}
