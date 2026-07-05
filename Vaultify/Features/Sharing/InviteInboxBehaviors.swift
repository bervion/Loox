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
    /// FIFO of discovered invites. An invite leaves the queue ONLY on a user
    /// response (accept / not now) — reconcile passes re-discover anything
    /// unanswered, and `markSeen` fires on response, so a lock or kill while
    /// the alert is up cannot swallow an invite (review H2).
    @State private var pendingInvites: [InviteEnvelope] = []
    /// The invite whose alert is up. Explicit and decoupled from the queue:
    /// an in-flight accept must not let the SAME invite re-present, and a
    /// dismissal must remove exactly this invite by id (review H1).
    @State private var presentedInvite: InviteEnvelope?
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
            .alert("Share invitation", isPresented: invitePresented, presenting: presentedInvite) { invite in
                Button("Not Now", role: .cancel) { finish(invite, accept: false) }
                Button("Accept") { finish(invite, accept: true) }
            } message: { _ in
                Text("Someone shared an item with you in Loox Password. Accept to see it in \"Shared with Me\" on Home.")
            }
            .alert("Couldn't accept the invitation",
                   isPresented: Binding(get: { acceptError != nil },
                                        set: { if !$0 { acceptError = nil; presentNextIfIdle() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: acceptError ?? "")
            }
    }

    private var invitePresented: Binding<Bool> {
        Binding(get: { presentedInvite != nil },
                // Swipe/system dismissal without a button: keep the invite
                // queued (NOT seen) — it re-presents on the next pass.
                set: { if !$0 { presentedInvite = nil } })
    }

    private func presentNextIfIdle() {
        guard presentedInvite == nil, acceptError == nil else { return }
        presentedInvite = pendingInvites.first
    }

    /// A real user response: burn the dedup id, drop from the queue, then
    /// accept (async) or move on.
    private func finish(_ invite: InviteEnvelope, accept: Bool) {
        env.inviteInbox.markSeen(inviteID: invite.inviteID)
        pendingInvites.removeAll { $0.inviteID == invite.inviteID }
        presentedInvite = nil
        guard accept else { presentNextIfIdle(); return }
        Task {
            do {
                guard let url = URL(string: invite.shareURL) else {
                    throw InviteLinkService.Failure.malformedLink
                }
                // U7: the fetched CKShare metadata must MATCH the envelope's
                // participant bindings — a mismatched drop is discarded.
                try await env.inviteLinks.acceptShare(
                    url: url,
                    expectedOwnerParticipantID: invite.ownerParticipantID,
                    expectedRecipientParticipantID: invite.recipientParticipantID)
                // Downstream is the standard acceptance resume: breadcrumb →
                // escrow/profile publish → the share appears in Shared with Me.
                presentNextIfIdle()
            } catch {
                acceptError = error.localizedDescription
            }
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
        presentNextIfIdle()
    }
}

extension View {
    /// Attach the recipient-side invite-inbox reconciler (see type docs).
    func inviteInboxBehaviors() -> some View { modifier(InviteInboxBehaviors()) }
}
