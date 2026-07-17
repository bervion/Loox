import Foundation
import OSLog

/// One analytics backend. The engine fans every event out to all registered
/// providers, so adding a destination later (self-hosted, PostHog, …) is a new
/// conformance + one `register` call — call sites never change.
@MainActor protocol AnalyticsProvider: AnyObject {
    func log(_ event: AnalyticsEvent)
    func setUserProperty(_ value: String?, forName name: String)
    /// Runtime consent switch — must stop the backend from recording anything
    /// (not just drop events the engine forwards).
    func setCollectionEnabled(_ enabled: Bool)
}

#if DEBUG
/// Console mirror so every event is visible while developing (Console.app /
/// Xcode, category "analytics") — the Firebase DebugView round trip is optional,
/// not required, to see what the app emits.
@MainActor final class ConsoleAnalyticsProvider: AnalyticsProvider {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vaultify",
                                category: "analytics")

    func log(_ event: AnalyticsEvent) {
        let parameters = event.parameters
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        logger.debug("▶ \(event.name, privacy: .public) \(parameters, privacy: .public)")
    }

    func setUserProperty(_ value: String?, forName name: String) {
        logger.debug("◆ \(name, privacy: .public)=\(value ?? "nil", privacy: .public)")
    }

    func setCollectionEnabled(_ enabled: Bool) {
        logger.debug("● collection \(enabled ? "enabled" : "disabled", privacy: .public)")
    }
}
#endif
