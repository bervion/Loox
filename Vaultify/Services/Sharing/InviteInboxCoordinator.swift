import Foundation

/// Owns the recipient's pending-invite queue (V1.2, V7): ONE reconcile path
/// (U6) feeds BOTH the quick-path alert (`InviteInboxBehaviors`) and the
/// notifications screen — push is a hint, the public-db inbox is the truth,
/// and an invite leaves the queue only on a user response.
@MainActor @Observable final class InviteInboxCoordinator {
    private(set) var pendingInvites: [InviteEnvelope] = []
    /// True while the notifications screen is frontmost — the shell alert
    /// stands down so the same invite isn't presented twice at once.
    var alertsSuppressed = false
    private var reconciling = false

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let session: VaultSession
    @ObservationIgnored private let escrow: ParticipantEscrowService
    @ObservationIgnored private let inbox: InviteInboxService
    @ObservationIgnored private let links: InviteLinkService

    init(settings: SettingsStore, session: VaultSession,
         escrow: ParticipantEscrowService, inbox: InviteInboxService,
         links: InviteLinkService) {
        self.settings = settings
        self.session = session
        self.escrow = escrow
        self.inbox = inbox
        self.links = links
    }

    /// Arm + pull + enqueue. Gated by `approvalModeEnabled` (first-time
    /// recipients ride the link tier) and the unlocked vault (the participant
    /// identity lives under the Vault Key). Single-flight.
    func reconcile() async {
        guard settings.approvalModeEnabled,
              let vaultKey = session.vaultKey?.bytes,
              !reconciling else { return }
        reconciling = true
        defer { reconciling = false }
        guard let identity = try? await escrow.ensureIdentity(vaultKey: vaultKey) else { return }
        await inbox.ensureArmed(identity: identity)
        let discovered = await inbox.reconcile(identity: identity)
        guard !discovered.isEmpty else { return }
        let queued = Set(pendingInvites.map(\.inviteID))
        pendingInvites.append(contentsOf: discovered.filter { !queued.contains($0.inviteID) })
    }

    /// "Not now": burn the dedup id, drop from the queue — never re-prompted.
    func dismiss(_ invite: InviteEnvelope) {
        inbox.markSeen(inviteID: invite.inviteID)
        pendingInvites.removeAll { $0.inviteID == invite.inviteID }
    }

    /// Accept: burn dedup + run the U7-cross-checked CloudKit acceptance.
    /// Downstream is the standard resume (breadcrumb → escrow/profile →
    /// the share appears as a projected item).
    func accept(_ invite: InviteEnvelope) async throws {
        dismiss(invite)
        guard let url = URL(string: invite.shareURL) else {
            throw InviteLinkService.Failure.malformedLink
        }
        try await links.acceptShare(
            url: url,
            expectedOwnerParticipantID: invite.ownerParticipantID,
            expectedRecipientParticipantID: invite.recipientParticipantID)
    }
}
