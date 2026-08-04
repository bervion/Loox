import Foundation

/// Per-flow completion state, persisted so a tour never replays.
///
/// Deliberately plain `UserDefaults` (same shape as `SettingsStore`): this is
/// UI progress, not vault data — it must survive a lock, and it must never
/// travel inside the encrypted store or sync between devices, where a tour
/// "already seen" on one device would silently skip it on a new one.
nonisolated final class TutorialStore {
    enum State: String {
        case notStarted
        case completed
        case skipped
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ flowID: String) -> String { "tutorial_state_\(flowID)" }

    func state(of flowID: String) -> State {
        defaults.string(forKey: key(flowID)).flatMap(State.init(rawValue:)) ?? .notStarted
    }

    /// Whether the flow still has something to show. A skipped tour counts as
    /// answered: the user said no once, and asking again is nagging.
    func shouldPresent(_ flowID: String) -> Bool {
        TutorialFeature.enabled && state(of: flowID) == .notStarted
    }

    func mark(_ flowID: String, _ state: State) {
        defaults.set(state.rawValue, forKey: key(flowID))
    }

    func reset(_ flowID: String) {
        defaults.removeObject(forKey: key(flowID))
    }

    /// Forget every answer, so the tours run again from the start. Reachable
    /// from Settings: someone who skipped a tour on day one, or who inherits a
    /// vault set up by somebody else, has no other way back to it.
    /// Main-actor bound because the flow catalog it enumerates is UI data that
    /// lives on the main actor; every caller (Settings, the coordinator) is
    /// already there.
    @MainActor
    func resetAll() {
        for id in TutorialFlow.allFlowIDs { reset(id) }
    }
}
