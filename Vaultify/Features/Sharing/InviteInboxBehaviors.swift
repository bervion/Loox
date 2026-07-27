import SwiftUI

/// One voice for both acceptance paths (universal link and rendezvous inbox):
/// name the CloudKit-authenticated sender, or say plainly that it could not be
/// confirmed. An accepted share writes into AutoFill, so the recipient has to
/// see WHO is behind it before deciding — and a missing identity is stated,
/// never papered over with an invented name.
enum InvitePrompt {
    static func title(sender: String?) -> Text {
        guard let sender else { return Text("Accept this share invitation") }
        return Text("\(sender) wants to share with you")
    }

    static func message(sender: String?) -> Text {
        guard sender != nil else {
            return Text("Loox could not confirm who sent this invitation. Accept only if you were expecting it.")
        }
        return Text("This name comes from their iCloud account. Accept to add the shared item to your vault.")
    }

    /// Compact form for list rows, where the full prompt does not fit.
    static func senderLine(sender: String?) -> Text {
        guard let sender else { return Text("Sender not confirmed") }
        return Text("From \(sender)")
    }
}

/// Quick-path alert over `InviteInboxCoordinator`'s queue, attached to the
/// unlocked shell. Reconcile triggers (launch, foreground, push-hint) live
/// here because the shell is the reliable lifecycle anchor; the queue and
/// accept/dismiss semantics live in the coordinator, shared with the
/// notifications screen (V7).
struct InviteInboxBehaviors: ViewModifier {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    /// The invite whose alert is up. Explicit and decoupled from the queue:
    /// an in-flight accept must not let the SAME invite re-present, and a
    /// dismissal must remove exactly this invite by id (review H1).
    @State private var presentedInvite: InviteEnvelope?
    @State private var acceptError: String?
    /// True while an accept is in flight — the NEXT invite must not present
    /// until the current one resolves (review M2).
    @State private var accepting = false

    func body(content: Content) -> some View {
        content
            .task { await reconcileAndPresent() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await reconcileAndPresent() } }
            }
            // Push = wake-up hint only (U6); the reconcile query is the truth.
            .onReceive(NotificationCenter.default.publisher(for: .inviteRendezvousReceived)) { _ in
                Task { await reconcileAndPresent() }
            }
            // The notifications screen consumes the same queue — follow it,
            // and resume presenting when it releases the suppression.
            .onChange(of: env.inviteInboxCoordinator.pendingInvites.first?.inviteID) { _, _ in
                presentNextIfIdle()
            }
            .onChange(of: env.inviteInboxCoordinator.alertsSuppressed) { _, suppressed in
                if !suppressed { presentNextIfIdle() }
            }
            .alert(InvitePrompt.title(sender: presentedSender),
                   isPresented: invitePresented, presenting: presentedInvite) { invite in
                Button("Not now", role: .cancel) { finish(invite, accept: false) }
                Button("Accept") { finish(invite, accept: true) }
            } message: { invite in
                InvitePrompt.message(sender: env.inviteInboxCoordinator.senderName(for: invite))
            }
            .alert("Couldn't accept the invitation",
                   isPresented: Binding(get: { acceptError != nil },
                                        set: { if !$0 { acceptError = nil; presentNextIfIdle() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: acceptError ?? "")
            }
    }

    /// The alert title is built outside the `presenting:` closure, so the
    /// sender has to be looked up here too.
    private var presentedSender: String? {
        presentedInvite.flatMap { env.inviteInboxCoordinator.senderName(for: $0) }
    }

    private var invitePresented: Binding<Bool> {
        Binding(get: { presentedInvite != nil },
                // Swipe/system dismissal without a button: keep the invite
                // queued (NOT seen) — it re-presents on the next pass.
                set: { if !$0 { presentedInvite = nil } })
    }

    private func presentNextIfIdle() {
        guard !env.uiTestConfiguration.isEnabled,
              presentedInvite == nil, acceptError == nil, !accepting,
              !env.inviteInboxCoordinator.alertsSuppressed else { return }
        presentedInvite = env.inviteInboxCoordinator.pendingInvites.first
    }

    private func finish(_ invite: InviteEnvelope, accept: Bool) {
        presentedInvite = nil
        guard accept else {
            env.inviteInboxCoordinator.dismiss(invite)
            presentNextIfIdle()
            return
        }
        accepting = true
        Task {
            defer { accepting = false }
            do {
                try await env.inviteInboxCoordinator.accept(invite)
                presentNextIfIdle()
            } catch {
                // The invite stays queued (burn happens only on success) —
                // after the error alert dismisses, it re-presents for retry.
                acceptError = error.localizedDescription
            }
        }
    }

    private func reconcileAndPresent() async {
        guard !env.uiTestConfiguration.isEnabled else { return }
        await env.inviteInboxCoordinator.reconcile()
        presentNextIfIdle()
    }
}

extension View {
    /// Attach the recipient-side invite-inbox quick-path alert (see type docs).
    func inviteInboxBehaviors() -> some View { modifier(InviteInboxBehaviors()) }
}
