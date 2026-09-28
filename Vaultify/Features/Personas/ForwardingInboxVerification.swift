import SwiftUI

/// Runs the two forwarding-inbox verification commands — send the confirmation
/// email, and read back whether it was confirmed — and owns the state both of
/// them need.
///
/// Both screens that offer verification (the inbox list and one inbox's detail)
/// previously fired the relay call straight from the button with no state at
/// all: no busy indicator, no guard against a second tap, and no answer on
/// success. Tapping "Confirm email" four times sent the user four emails and
/// looked identical to tapping it once. Everything that prevents that lives
/// here, in one place, so the two screens cannot drift apart again.
@MainActor @Observable final class ForwardingInboxVerification {
    enum Activity: Equatable {
        case sending
        case checking
    }

    /// What the user reads after an action. Success and failure share one
    /// surface, so every tap ends in a sentence rather than in silence.
    struct Outcome: Equatable {
        var title: String
        var body: String
        /// The failure is a Private Email identity this vault can't open, so the
        /// alert offers the deliberate replacement (`startNewIdentity`).
        var offersNewIdentity = false
    }

    /// Fallback wait before the confirmation email may be sent again, used only
    /// when the relay does not name its own. The backend is the authority.
    private static let fallbackResendCooldown = 60

    private(set) var activity: Activity?
    private(set) var busyInboxID: String?
    var outcome: Outcome?

    /// When each inbox may be sent another confirmation email.
    private var resendAvailableAt: [String: Date] = [:]
    /// Bumped once a second while any cooldown runs, so countdown labels
    /// re-render without every view owning a timer.
    private(set) var countdownTick = 0
    /// Holds itself weakly, so it ends on its own once the screen goes away —
    /// which is why there is no `deinit` to cancel it from (a `@MainActor` class
    /// cannot touch its own isolated state there).
    private var countdown: Task<Void, Never>?

    func isBusy(_ inbox: ForwardingInbox) -> Bool { busyInboxID == inbox.id }

    /// Seconds until this inbox can be sent another confirmation email; 0 when
    /// it can be sent now.
    func resendWait(for inbox: ForwardingInbox) -> Int {
        _ = countdownTick   // observation dependency for the ticking label
        guard let ready = resendAvailableAt[inbox.id] else { return 0 }
        return max(0, Int(ready.timeIntervalSinceNow.rounded(.up)))
    }

    func canSend(to inbox: ForwardingInbox) -> Bool {
        busyInboxID == nil && resendWait(for: inbox) == 0
    }

    /// Begin or resend ownership verification. The relay sends the email, so a
    /// second call is a second email in the user's inbox — this refuses to make
    /// one while a call is in flight or while the cooldown the relay asked for
    /// is still running.
    func send(to inbox: ForwardingInbox, relay: RelayService) async {
        guard canSend(to: inbox) else { return }
        busyInboxID = inbox.id
        activity = .sending
        defer { busyInboxID = nil; activity = nil }
        do {
            let state = try await relay.beginDestinationVerification(inbox)
            startCooldown(inbox, seconds: state.resendAfterSeconds ?? Self.fallbackResendCooldown)
            Haptics.success()
            outcome = Outcome(
                title: appString("Check your inbox"),
                body: appString("We sent a confirmation link to \(EmailMask.masked(inbox.email)). Open it to finish setting up this forwarding address."))
        } catch {
            report(error)
        }
    }

    /// Read the confirmation result. Read-only and unmetered, so this needs no
    /// cooldown — only a guard against overlapping calls.
    func check(_ inbox: ForwardingInbox, relay: RelayService) async {
        guard busyInboxID == nil else { return }
        busyInboxID = inbox.id
        activity = .checking
        defer { busyInboxID = nil; activity = nil }
        do {
            let state = try await relay.refreshDestinationStatus(inbox)
            let status = state.flatMap { DestinationVerificationStatus(rawValue: $0.status) }
            if status == .verified {
                Haptics.success()
                outcome = Outcome(title: appString("Confirmed"),
                                  body: appString("This address is verified. Private addresses can forward to it now."))
            } else {
                // Not an error: the link is simply still unopened. Saying so
                // beats a spinner that stops with nothing changed on screen.
                Haptics.warning()
                outcome = Outcome(
                    title: appString("Not confirmed yet"),
                    body: appString("Open the confirmation link we emailed to \(EmailMask.masked(inbox.email)), then check again."))
            }
        } catch {
            report(error)
        }
    }

    /// The recovery the failure alert offered: replace a Private Email identity
    /// this vault can't open. The answer lands on the same surface as every
    /// other outcome.
    func startNewIdentity(relay: RelayService) async {
        let result = await RelayIdentityRecovery.startNewIdentity(using: relay)
        outcome = Outcome(title: result.title, body: result.message)
    }

    private func report(_ error: Error) {
        Haptics.error()
        if let failure = error as? RelayService.Failure {
            outcome = Outcome(title: failure.userTitle, body: failure.userMessage,
                              offersNewIdentity: failure.offersNewIdentity)
        } else {
            outcome = Outcome(title: appString("Couldn’t reach the relay"),
                              body: appString("Check your connection and iCloud, then try again."))
        }
    }

    private func startCooldown(_ inbox: ForwardingInbox, seconds: Int) {
        resendAvailableAt[inbox.id] = Date().addingTimeInterval(TimeInterval(max(0, seconds)))
        guard countdown == nil else { return }
        countdown = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                countdownTick &+= 1
                // Stop ticking once every cooldown has run out — the countdown
                // exists to redraw labels, not to keep a timer alive forever.
                if resendAvailableAt.values.allSatisfy({ $0 <= Date() }) {
                    resendAvailableAt.removeAll()
                    countdown = nil
                    return
                }
            }
        }
    }
}
