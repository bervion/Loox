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

    /// DEBUG affordance so the tours can be replayed while building them.
    func reset(_ flowID: String) {
        defaults.removeObject(forKey: key(flowID))
    }
}
