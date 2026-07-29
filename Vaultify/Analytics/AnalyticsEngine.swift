import Foundation
import OSLog
import SwiftUI

/// Small, fixed set of GA4 user properties. Low-cardinality setting states only —
/// a user property is attached to EVERY event, so nothing identifying belongs here.
nonisolated enum AnalyticsUserProperty: String {
    case subscriptionTier = "subscription_tier"
    case appLanguage = "app_language"
    case icloudSync = "icloud_sync"
}

/// Central analytics facade. Call sites log typed catalog events
/// (`AnalyticsEngine.shared.log(.itemCreated(.login))`); the engine gates on user
/// consent, DEBUG-validates against `AnalyticsPolicy`, and fans out to every
/// registered `AnalyticsProvider`. Scaling later = new provider or new catalog
/// entry — never a new pathway.
@MainActor final class AnalyticsEngine {
    static let shared = AnalyticsEngine()

    private var providers: [AnalyticsProvider] = []
    /// Mirrors `SettingsStore.analyticsEnabled` (kept in sync by its `didSet`).
    /// Belt and suspenders with the provider-level collection switch: a disabled
    /// engine drops events before any provider sees them.
    private var enabled = SettingsStore.isAnalyticsEnabled()
    /// Bulk operations (vault import, onboarding seeds) run with per-item events
    /// suppressed — 500 imported logins are one `vault_imported`, not 500
    /// `item_created`.
    private var suppressionDepth = 0
    /// Last screen logged — SwiftUI fires spurious duplicate `onAppear`s; an exact
    /// consecutive repeat is noise, a different screen is a real transition.
    private var lastScreen: String?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vaultify",
                                category: "analytics")

    /// Call once from app launch, before any event. Safe without a Firebase
    /// config: the app then runs with the DEBUG console mirror only.
    static func bootstrap() {
        let engine = shared
        guard engine.providers.isEmpty else { return }
        #if DEBUG
        engine.providers.append(ConsoleAnalyticsProvider())
        #endif
        if let firebase = FirebaseAnalyticsProvider.bootstrapped() {
            engine.providers.append(firebase)
        } else {
            engine.logger.warning("GoogleService-Info.plist not bundled — GA4 disabled, events stay on-device")
        }
        engine.applyCollectionState()
    }

    // MARK: Consent

    /// Driven by `SettingsStore.analyticsEnabled.didSet` — never call from
    /// feature code. Turning OFF logs the farewell first (while still allowed),
    /// turning ON logs right after the switch so the choice itself is measurable.
    func setEnabled(_ newValue: Bool) {
        guard newValue != enabled else { return }
        if newValue {
            enabled = true
            applyCollectionState()
            log(.analyticsEnabled)
        } else {
            log(.analyticsDisabled)
            enabled = false
            applyCollectionState()
        }
    }

    private func applyCollectionState() {
        for provider in providers { provider.setCollectionEnabled(enabled) }
    }

    // MARK: Logging

    func log(_ event: AnalyticsEvent) {
        guard enabled, suppressionDepth == 0 else { return }
        #if DEBUG
        let issues = AnalyticsPolicy.issues(in: event)
        assert(issues.isEmpty, "Invalid analytics event: \(issues.joined(separator: "; "))")
        #endif
        for provider in providers { provider.log(sanitized(event)) }
    }

    /// Screen views route here (not `log`) for the duplicate-`onAppear` guard.
    func logScreen(_ name: String) {
        guard name != lastScreen else { return }
        lastScreen = name
        log(.screenView(name))
    }

    func setUserProperty(_ property: AnalyticsUserProperty, _ value: String?) {
        guard enabled else { return }
        let capped = value.map { String($0.prefix(AnalyticsPolicy.userPropertyValueLimit)) }
        for provider in providers { provider.setUserProperty(capped, forName: property.rawValue) }
    }

    /// The standing user-property set, one place. Call at launch and whenever a
    /// constituent changes (purchase, language switch, sync toggle).
    func refreshUserProperties(tier: LooxTier, language: String, iCloudSyncEnabled: Bool) {
        let tierName: String = switch tier {
        case .free: "free"
        case .plus: "plus"
        case .max: "max"
        }
        setUserProperty(.subscriptionTier, tierName)
        setUserProperty(.appLanguage, language)
        setUserProperty(.icloudSync, iCloudSyncEnabled ? "on" : "off")
    }

    /// Run `body` with event logging suppressed (re-entrant). For bulk flows whose
    /// per-item events would flood the stream — log ONE summary event after.
    func runSuppressed<R>(_ body: () throws -> R) rethrows -> R {
        suppressionDepth += 1
        defer { suppressionDepth -= 1 }
        return try body()
    }

    /// Release builds keep sending instead of asserting: overlong string values
    /// are truncated so GA4 doesn't silently discard the whole event.
    private func sanitized(_ event: AnalyticsEvent) -> AnalyticsEvent {
        let needsTruncation = event.parameters.contains {
            if case .string(let value) = $0.value {
                return value.count > AnalyticsPolicy.parameterStringValueLimit
            }
            return false
        }
        guard needsTruncation else { return event }
        let capped = event.parameters.mapValues { value -> AnalyticsValue in
            if case .string(let string) = value {
                return .string(String(string.prefix(AnalyticsPolicy.parameterStringValueLimit)))
            }
            return value
        }
        return AnalyticsEvent(event.name, capped)
    }
}

// MARK: - Screen tracking

private struct AnalyticsScreenModifier: ViewModifier {
    let name: String
    func body(content: Content) -> some View {
        content.onAppear {
            AnalyticsEngine.shared.logScreen(name)
            // Crash reporting has its own consent and its own gate — the screen
            // a freeze happened on must not depend on the GA4 answer.
            CrashReporter.shared.set(.activeScreen(name))
        }
    }
}

extension View {
    /// Logs a GA4 `screen_view` when the screen appears. `name` is a fixed
    /// snake_case identifier ("home", "item_detail") — never a localized title.
    func analyticsScreen(_ name: String) -> some View {
        modifier(AnalyticsScreenModifier(name: name))
    }
}
