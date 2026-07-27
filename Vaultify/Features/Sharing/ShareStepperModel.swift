import SwiftUI

/// Visual state of one step in the owner-facing 4-step share stepper — pure
/// presentation, derived from the already-persisted `ShareLifecycle`. No
/// protocol/lifecycle change: this only re-labels the 4 states `SharingStore`
/// already tracks (inviteSent/accepted/readyForCeremony/active) into the
/// canonical 4-step language used across Home, Item Detail, and the resume
/// sheet (design "12" — pending-share persistence).
enum ShareStepState { case done, current, todo }

struct ShareStepperStep: Identifiable {
    let id: Int
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let state: ShareStepState
}

enum ShareStepper {
    /// The 4 user-facing steps for a given lifecycle status. Step 1 (invite
    /// sent) is always "done" here — a record only exists in `SharingStore`
    /// once the invite was created.
    static func steps(for status: ShareLifecycle) -> [ShareStepperStep] {
        let acceptedOrLater = status.rank >= ShareLifecycle.accepted.rank
        let readyOrLater = status.rank >= ShareLifecycle.readyForCeremony.rank
        let active = status == .active
        return [
            ShareStepperStep(id: 1, title: "Invite sent", subtitle: "via iCloud", state: .done),
            ShareStepperStep(
                id: 2, title: "Waiting for them to accept",
                subtitle: acceptedOrLater
                    ? "They accepted the invitation."
                    : "They haven't opened the invitation yet. Nudge them below.",
                state: acceptedOrLater ? .done : .current),
            // Their device publishes the key the share is sealed to. Nothing is
            // asked of the owner here — the scope was set when the invite was
            // created, so this finishes on its own once the key arrives.
            ShareStepperStep(
                id: 3, title: "Setting up on their device",
                subtitle: active
                    ? "Done."
                    : "Finishes by itself once their device is ready.",
                state: active ? .done : (readyOrLater ? .current : .todo)),
            ShareStepperStep(
                id: 4, title: "Access active",
                subtitle: "They can use what you allowed. Revoke anytime.",
                state: active ? .done : .todo),
        ]
    }

    /// Owner-facing one-line status for a per-recipient row (Item Detail
    /// "Shared with" list, design 12b).
    static func detailSubtitle(for status: ShareLifecycle) -> LocalizedStringResource {
        switch status {
        case .inviteSent: "Invite sent. Waiting to accept"
        case .accepted: "Accepted. Finishing on their device"
        case .readyForCeremony: "Finishing setup"
        case .active: "Active"
        }
    }
}

/// Glanceable 4-segment progress bar mirroring `ShareStepper.steps` — used
/// under a pending recipient row so "where is this stuck" reads without
/// opening the resume sheet (design 12b).
struct ShareMiniProgressBar: View {
    let status: ShareLifecycle
    @Environment(AppEnvironment.self) private var env

    private var steps: [ShareStepperStep] { ShareStepper.steps(for: status) }
    private var currentStepNumber: Int {
        steps.first(where: { $0.state != .done })?.id ?? steps.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                ForEach(steps) { step in
                    Capsule()
                        .fill(segmentColor(step.state))
                        .frame(height: 3)
                }
            }
            Text("Step \(currentStepNumber) of \(steps.count)")
                .vaultType(.caption).themedForeground(.tertiary)
        }
    }

    private func segmentColor(_ state: ShareStepState) -> Color {
        switch state {
        case .done: env.theme.active.color(.success)
        case .current: env.theme.active.color(.warning)
        case .todo: Color(rgb: env.theme.active.separator)
        }
    }
}
