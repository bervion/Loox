import Foundation

/// Owns the recipient's pending-invite queue (V1.2, V7): ONE reconcile path
/// (U6) feeds BOTH the quick-path alert (`InviteInboxBehaviors`) and the
/// notifications screen — push is a hint, the public-db inbox is the truth,
/// and an invite leaves the queue only on a user response.
@MainActor @Observable final class InviteInboxCoordinator {
    private(set) var pendingInvites: [InviteEnvelope] = []
    /// CloudKit-authenticated sender per invite (inviteID → display name).
    /// The envelope carries only opaque participant ids, so the human name is
    /// resolved from the share metadata BEFORE the invite is queued: no accept
    /// prompt may appear without either an identity or an honest "not
    /// confirmed" line.
    private(set) var senderNames: [String: String] = [:]
    /// True while the notifications screen is frontmost — the shell alert
    /// stands down so the same invite isn't presented twice at once.
    var alertsSuppressed = false
    private var reconciling = false

    /// Invites already written to history. Deliberately NOT the inbox's `seen`
    /// set: `seen` means the user answered, and a swipe-dismissed alert must
    /// stay unanswered so it re-presents. Without a durable record here, every
    /// launch rediscovers an ignored invite and logs another "received" row
    /// until it evicts the real history.
    private static let loggedReceivedKey = "invite_inbox_logged_received_ids_v1"
    private static let loggedReceivedCap = 200

    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let session: VaultSession
    @ObservationIgnored private let escrow: ParticipantEscrowService
    @ObservationIgnored private let inbox: InviteInboxService
    @ObservationIgnored private let links: InviteLinkService
    /// Optional history sink (set by AppEnvironment after construction).
    @ObservationIgnored weak var history: NotificationHistoryStore?

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
        let fresh = discovered.filter { !queued.contains($0.inviteID) }
        // Retry the identity for anything still unnamed, already queued or
        // not: an invite discovered while offline must not stay stuck on
        // "sender not confirmed" for the rest of the launch.
        for envelope in discovered where senderNames[envelope.inviteID] == nil {
            if let url = URL(string: envelope.shareURL),
               let name = await links.resolveSenderName(shareURL: url) {
                senderNames[envelope.inviteID] = name
            }
        }
        for envelope in fresh {
            if recordReceivedOnce(envelope.inviteID) {
                history?.log(.inviteReceived, label: senderNames[envelope.inviteID])
            }
        }
        // Queued only once the identity lookup settled, so the alert this
        // triggers can already name the sender.
        pendingInvites.append(contentsOf: fresh)
    }

    /// The sender to show for an invite, nil when CloudKit gave us no name.
    func senderName(for invite: InviteEnvelope) -> String? { senderNames[invite.inviteID] }

    /// "Not now": burn the dedup id, drop from the queue — never re-prompted.
    func dismiss(_ invite: InviteEnvelope) {
        inbox.markSeen(inviteID: invite.inviteID)
        if pendingInvites.contains(where: { $0.inviteID == invite.inviteID }) {
            history?.log(.inviteDismissed, label: senderNames[invite.inviteID])
        }
        pendingInvites.removeAll { $0.inviteID == invite.inviteID }
        senderNames[invite.inviteID] = nil
    }

    /// Accept: run the U7-cross-checked CloudKit acceptance, and burn the
    /// dedup id ONLY on success — a transient CloudKit failure must leave
    /// the invite queued for retry, not permanently lost (review H2).
    /// Downstream is the standard resume (breadcrumb → escrow/profile →
    /// the share appears as a projected item).
    func accept(_ invite: InviteEnvelope) async throws {
        guard let url = URL(string: invite.shareURL) else {
            dismiss(invite) // Malformed can never succeed — burn it.
            throw InviteLinkService.Failure.malformedLink
        }
        try await links.acceptShare(
            url: url,
            expectedOwnerParticipantID: invite.ownerParticipantID,
            expectedRecipientParticipantID: invite.recipientParticipantID)
        inbox.markSeen(inviteID: invite.inviteID)
        pendingInvites.removeAll { $0.inviteID == invite.inviteID }
        history?.log(.inviteAccepted, label: senderNames[invite.inviteID])
        senderNames[invite.inviteID] = nil
    }

    /// True the first time this invite is written to history, false ever
    /// after. FIFO-capped: the oldest ids belong to long-expired drops.
    private func recordReceivedOnce(_ inviteID: String) -> Bool {
        var logged = UserDefaults.standard.stringArray(forKey: Self.loggedReceivedKey) ?? []
        guard !logged.contains(inviteID) else { return false }
        logged.append(inviteID)
        if logged.count > Self.loggedReceivedCap {
            logged.removeFirst(logged.count - Self.loggedReceivedCap)
        }
        UserDefaults.standard.set(logged, forKey: Self.loggedReceivedKey)
        return true
    }
}
