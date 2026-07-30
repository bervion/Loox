import SwiftUI

/// One step of a tutorial flow: what to highlight and what to say about it.
struct TutorialStep: Identifiable {
    let id: String
    /// Anchor to spotlight. `nil` shows a centered card with no cut-out —
    /// used for an opening or closing beat that is about the app as a whole.
    var anchor: String?
    var shape: TutorialSpotlightShape = .rounded
    var title: LocalizedStringResource
    var message: LocalizedStringResource
    /// True when the step asks the user to press the real control: the
    /// spotlight then passes taps through instead of advancing the tour.
    var awaitsRealTap: Bool = false
}

/// A named sequence of steps. Flows are data — the runner in
/// `TutorialCoordinator` owns all behavior, so adding a tour is adding a
/// constant here plus anchors on the screen it describes.
struct TutorialFlow: Identifiable {
    let id: String
    let steps: [TutorialStep]
}

extension TutorialFlow {
    /// Every flow the app ships. Drives "Show tutorials again" in Settings, and
    /// the test that keeps flow anchors honest.
    static var all: [TutorialFlow] { [.firstRun, .watchtower, .sharing, .quickView, .privateEmail] }
    static var allFlowIDs: [String] { all.map(\.id) }

    /// Flows that run INSIDE a sheet and are therefore hosted there rather
    /// than at the root, whose overlay a sheet would cover.
    static let sheetHostedFlowIDs: Set<String> = ["sharing", "quick-view"]

    /// First unlock after onboarding: where things live, in three beats.
    static let firstRun = TutorialFlow(id: "first-run", steps: [
        TutorialStep(id: "add-item",
                     anchor: TutorialAnchorID.homeAddItem,
                     title: "Add your first item",
                     message: "Logins, cards, notes, and passkeys all live here. Loox encrypts each one on this device."),
        TutorialStep(id: "security",
                     anchor: TutorialAnchorID.homeSecurity,
                     title: "Check your security",
                     message: "Loox reviews password strength, reuse, and known leaks, then walks you through the fixes."),
        // Closing beat, deliberately anchorless: it is about the vault as a
        // whole, and a centered card reads as a summary rather than a pointer.
        TutorialStep(id: "on-device",
                     title: "Everything stays on this device",
                     message: "Your items are encrypted here and unlocked only by you. Turn on iCloud Sync in Settings when you want them on your other devices."),
    ])

    /// First visit to Security: what the number means and where the work is.
    static let watchtower = TutorialFlow(id: "watchtower", steps: [
        TutorialStep(id: "score",
                     anchor: TutorialAnchorID.watchtowerScore,
                     // The anchor spans the whole ring block — a rounded window
                     // reads as "this surface", not a keyhole around the dial.
                     shape: .rounded,
                     title: "Your vault health score",
                     message: "One number out of 1000, from password strength, reuse, known leaks, and how much two-factor protection you have. Tap it to see what moved it."),
        TutorialStep(id: "run-audit",
                     anchor: TutorialAnchorID.watchtowerRunAudit,
                     shape: .capsule,
                     title: "Run a check anytime",
                     message: "Most checks run on this device. Leak checks send only the first five characters of a hashed password, never the password."),
    ])

    /// First time the owner sends an item to a browser.
    static let quickView = TutorialFlow(id: "quick-view", steps: [
        TutorialStep(id: "what",
                     title: "Open this on your computer",
                     message: "Scan the code with your computer's browser and the fields you approve appear there. Nothing is typed, and nothing is stored on the page."),
        TutorialStep(id: "expiry",
                     title: "It closes by itself",
                     message: "The session lasts minutes, not days. When it ends the page goes blank, and you can end it from here at any time."),
    ])

    /// First visit to Private Email.
    static let privateEmail = TutorialFlow(id: "private-email", steps: [
        TutorialStep(id: "what",
                     title: "A different address for each site",
                     message: "Give a site its own address instead of your real one. Mail still reaches your inbox, and the site never learns where."),
        TutorialStep(id: "control",
                     title: "Turn one off and the mail stops",
                     message: "If an address starts getting spam, pause or delete it. That address stops forwarding; every other one keeps working."),
    ])

    /// First time the owner opens sharing on an item.
    static let sharing = TutorialFlow(id: "sharing", steps: [
        TutorialStep(id: "what",
                     title: "Sharing keeps you in control",
                     message: "You choose which fields another person can use. Values you hand over are theirs to keep; the rest stays behind your approval."),
        TutorialStep(id: "approvals",
                     title: "Requests arrive as notifications",
                     message: "When they need a field you kept under approval, Loox notifies you and you decide right then. Without notifications those requests never reach you."),
    ])
}
