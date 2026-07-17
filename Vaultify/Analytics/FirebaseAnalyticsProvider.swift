import FirebaseAnalytics
import FirebaseCore
import Foundation

/// GA4 backend via Firebase Analytics — the `FirebaseAnalyticsCore` flavor
/// (GoogleAppMeasurementCore): full measurement, no AdSupport/IDFA, no ATT
/// entanglement. Linked into the app target only; the AutoFill and Safari
/// extensions must never carry telemetry.
@MainActor final class FirebaseAnalyticsProvider: AnalyticsProvider {

    /// Configures Firebase once and returns the provider — or nil when
    /// `GoogleService-Info.plist` isn't bundled (fork or dev machine without a
    /// Firebase project), in which case the app runs with analytics dark instead
    /// of crashing in `FirebaseApp.configure()`.
    static func bootstrapped() -> FirebaseAnalyticsProvider? {
        if FirebaseApp.app() == nil {
            guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
                return nil
            }
            FirebaseApp.configure()
        }
        return FirebaseAnalyticsProvider()
    }

    func log(_ event: AnalyticsEvent) {
        Analytics.logEvent(
            event.name,
            parameters: event.parameters.isEmpty
                ? nil
                : event.parameters.mapValues { $0.firebaseValue })
    }

    func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    func setCollectionEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
    }
}
