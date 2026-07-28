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
}
