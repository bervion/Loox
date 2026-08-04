import Foundation

/// How far an erase reaches. The two modes are deliberately distinct actions
/// with distinct copy: "on this device" used to be the wording while the code
/// also dropped the CloudKit zone, revoked nothing, and destroyed the only
/// credentials that could kill a live quick link.
nonisolated enum EraseScope: Sendable, Equatable {
    /// Everything Loox stored on this device. Remote copies (the iCloud vault,
    /// quick links, private-email aliases, shared logins) are left alone.
    case thisDevice
    /// The device plus every remote surface this device can still authorize a
    /// teardown for. Fail-closed: the wipe only runs once each step reports.
    case everywhere
}

/// One remote surface an "erase everywhere" tears down BEFORE the device wipe.
/// The ordering is load-bearing: every credential these steps need — the
/// quick-link revoke tokens, the relay principal key, the approval zone
/// registry — is destroyed by the local wipe.
nonisolated enum EraseStep: String, CaseIterable, Sendable {
    case quickLinks
    case emailAliases
    case approvalShares
    case inviteInbox
    case cloudVault

    /// What the user is told is still live when this step fails. Written per
    /// step rather than as a generic "step N failed" so the consequence is
    /// legible without knowing the architecture.
    func failureLine(count: Int) -> String {
        switch self {
        case .quickLinks:
            return String(format: appString("Quick links: %lld still readable"), count)
        case .emailAliases:
            return appString("Private email aliases are still forwarding")
        case .approvalShares:
            return appString("Shared logins are still shared")
        case .inviteInbox:
            return appString("Your invite inbox is still open")
        case .cloudVault:
            return appString("The iCloud copy is still there")
        }
    }
}

/// What one teardown step actually managed to do.
nonisolated struct EraseStepOutcome: Sendable, Equatable, Identifiable {
    let step: EraseStep
    /// Objects the step tried to tear down. Zero means there was nothing to do.
    let attempted: Int
    /// How many of them are still live afterwards.
    let failed: Int

    var id: String { step.rawValue }
    var succeeded: Bool { failed == 0 }

    init(step: EraseStep, attempted: Int, failed: Int) {
        self.step = step
        self.attempted = attempted
        self.failed = failed
    }

    /// Convenience for the steps that are one indivisible remote operation.
    static func single(_ step: EraseStep, succeeded: Bool) -> EraseStepOutcome {
        EraseStepOutcome(step: step, attempted: 1, failed: succeeded ? 0 : 1)
    }

    /// Convenience for a step with nothing to tear down.
    static func nothingToDo(_ step: EraseStep) -> EraseStepOutcome {
        EraseStepOutcome(step: step, attempted: 0, failed: 0)
    }
}

/// The per-step result of one teardown pass, plus the quick links whose revoke
/// tokens must outlive the wipe.
nonisolated struct EraseTeardownReport: Sendable, Equatable {
    private(set) var outcomes: [EraseStepOutcome] = []
    /// Links that are still live because their revoke call did not land. Their
    /// token is the ONLY thing that can ever kill them, so an erase keeps it
    /// instead of deleting it along with the vault.
    var unrevokedLinks: [LooxLinkRecord] = []

    init(outcomes: [EraseStepOutcome] = [], unrevokedLinks: [LooxLinkRecord] = []) {
        self.outcomes = outcomes
        self.unrevokedLinks = unrevokedLinks
    }

    var failures: [EraseStepOutcome] { outcomes.filter { !$0.succeeded } }
    var isClean: Bool { failures.isEmpty }
    /// Exactly what a Retry re-runs — the steps that succeeded are not repeated.
    var failedSteps: [EraseStep] { failures.map(\.step) }

    /// A fresh outcome replaces the previous one for the same step, so a retry
    /// that fixes one surface clears that line instead of appending a second.
    mutating func record(_ outcome: EraseStepOutcome) {
        outcomes.removeAll { $0.step == outcome.step }
        outcomes.append(outcome)
        outcomes.sort { lhs, rhs in
            let order = EraseStep.allCases
            return (order.firstIndex(of: lhs.step) ?? 0) < (order.firstIndex(of: rhs.step) ?? 0)
        }
    }

    var failureLines: [String] { failures.map { $0.step.failureLine(count: $0.failed) } }

    /// The whole alert body: what is still live, then what erasing now means.
    var failureMessage: String {
        var text = failureLines.joined(separator: "\n")
        text += "\n\n" + appString("If you erase now, these stay live until they expire.")
        if failures.contains(where: { $0.step == .quickLinks }) {
            text += " " + appString("The keys needed to turn those links off are kept on this device.")
        }
        return text
    }
}

/// The one erase state machine both platforms drive. iOS used to hold the
/// fail-closed relay precondition inside its Settings view, so the macOS
/// window called the raw erase and left aliases forwarding forever while the
/// CloudKit zone drop destroyed the alias list on every other device.
@MainActor @Observable final class EraseFlow {
    enum Phase: Equatable {
        case idle
        /// A bounded remote teardown is running.
        case tearingDown
        /// At least one surface is still live and the user has to decide.
        case blocked
    }

    private(set) var phase: Phase = .idle
    private(set) var report = EraseTeardownReport()

    @ObservationIgnored private weak var environment: AppEnvironment?

    /// Wired once by `AppEnvironment.init` (two-phase: the flow is a stored
    /// property of the thing it drives).
    func attach(to environment: AppEnvironment) {
        self.environment = environment
    }

    var isWorking: Bool { phase == .tearingDown }
    var isBlocked: Bool { phase == .blocked }

    /// Start an erase. `.thisDevice` never touches the network; `.everywhere`
    /// tears every remote surface down first and only wipes on a clean pass.
    func begin(_ scope: EraseScope) async {
        guard let environment, phase == .idle else { return }
        switch scope {
        case .thisDevice:
            environment.eraseThisDevice()
        case .everywhere:
            report = EraseTeardownReport()
            await run(steps: EraseStep.allCases)
        }
    }

    /// Re-run only the steps that are still live.
    func retry() async {
        let steps = report.failedSteps
        guard !steps.isEmpty else { return }
        await run(steps: steps)
    }

    /// Proceed with a known-incomplete teardown. The revoke material for the
    /// links that are still live is retained rather than destroyed — that is
    /// the difference between "we could not turn it off yet" and "nobody can
    /// ever turn it off".
    func eraseAnyway() {
        environment?.finishErase(retainingLinks: report.unrevokedLinks)
        reset()
    }

    func cancel() { reset() }

    private func run(steps: [EraseStep]) async {
        guard let environment else { return }
        phase = .tearingDown
        let pass = await environment.tearDownRemoteState(steps: steps)
        for outcome in pass.outcomes { report.record(outcome) }
        // Only a pass that actually re-ran the quick-link step may replace the
        // retained set; a retry of the alias step alone must not drop it.
        if steps.contains(.quickLinks) { report.unrevokedLinks = pass.unrevokedLinks }
        if report.isClean {
            environment.finishErase(retainingLinks: [])
            reset()
        } else {
            phase = .blocked
        }
    }

    private func reset() {
        phase = .idle
        report = EraseTeardownReport()
    }
}
