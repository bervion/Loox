import FirebaseCore
import FirebaseCrashlytics
import Foundation
import OSLog

/// Crash diagnostics via Firebase Crashlytics. Call sites set typed catalog keys
/// (`CrashReporter.shared.set(.vaultLockState("locked"))`) and report categorised
/// faults; the reporter gates on its OWN consent flag, DEBUG-validates against
/// `CrashReportPolicy`, and hands nothing else to the SDK.
///
/// SCOPE, so nobody plans around a capability that isn't here: Crashlytics
/// catches signals and uncaught exceptions, plus the non-fatals we record. It
/// does NOT report hangs on Apple platforms (ANR reporting is Android-only), and
/// a watchdog kill arrives as a SIGKILL no in-process handler can observe. A
/// frozen-but-alive app produces no report at all. Diagnosing a hang needs
/// MetricKit's `MXHangDiagnostic`, which is a separate pipeline.
///
/// There is deliberately NO `setUserID` here, and there must never be: a
/// Crashlytics installation linked to an account or vault id would make the
/// privacy manifest's `NSPrivacyCollectedDataTypeLinked = false` a false
/// declaration. Not exposing the call is the enforcement.
///
/// Consent is `SettingsStore.crashReportingEnabled`, separate from the GA4
/// toggle: someone who declines usage statistics may still want the crash that
/// lost their session diagnosed, and the reverse.
@MainActor final class CrashReporter {
    static let shared = CrashReporter()

    /// nil until `bootstrap()` finds a configured Firebase app — the reporter
    /// then stays dark instead of touching the SDK.
    private var crashlytics: Crashlytics?
    /// Mirrors `SettingsStore.crashReportingEnabled` (kept in sync by its
    /// `didSet`). Belt and suspenders with the SDK's own collection switch: a
    /// disabled reporter drops keys before Crashlytics stores them on disk.
    private var enabled = SettingsStore.isCrashReportingEnabled()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vaultify",
                                category: "crash")

    /// Call once from app launch, AFTER `AnalyticsEngine.bootstrap()` — that is
    /// where `FirebaseApp.configure()` happens, behind the bundled
    /// `GoogleService-Info.plist` check. Reusing that gate keeps a fork without
    /// a Firebase project running with crash reporting dark rather than
    /// crashing at startup.
    static func bootstrap() {
        let reporter = shared
        guard reporter.crashlytics == nil else { return }
        guard FirebaseApp.app() != nil else {
            reporter.logger.warning("Firebase not configured — crash reporting disabled, nothing leaves the device")
            return
        }
        reporter.crashlytics = Crashlytics.crashlytics()
        reporter.applyCollectionState()
    }

    // MARK: Consent

    /// Driven by `SettingsStore.crashReportingEnabled.didSet` — never call from
    /// feature code.
    func setEnabled(_ newValue: Bool) {
        guard newValue != enabled else { return }
        enabled = newValue
        applyCollectionState()
    }

    private func applyCollectionState() {
        #if DEBUG
        // Development crashes would drown the production dashboard, and the
        // state a debugger produces is not the state a shipped app produces.
        crashlytics?.setCrashlyticsCollectionEnabled(false)
        #else
        crashlytics?.setCrashlyticsCollectionEnabled(enabled)
        #endif
    }

    // MARK: Reporting

    /// Attach a catalog key to every subsequent report. Keys are sticky: the
    /// last value set for a name is what the next crash carries.
    func set(_ key: CrashReportKey) {
        #if DEBUG
        let issues = CrashReportPolicy.issues(in: key)
        assert(issues.isEmpty, "Invalid crash key: \(issues.joined(separator: "; "))")
        logger.debug("◆ \(key.name, privacy: .public)=\(key.value.description, privacy: .public)")
        #endif
        guard enabled, let crashlytics else { return }
        crashlytics.setCustomValue(key.value.crashlyticsValue, forKey: key.name)
    }

    /// Report a handled failure as a non-fatal. Takes a CATEGORY, never a caught
    /// error — see `CrashReportFault` for why the `NSError` is built from fixed
    /// literals instead.
    func record(_ fault: CrashReportFault) {
        #if DEBUG
        let issues = CrashReportPolicy.issues(in: fault)
        assert(issues.isEmpty, "Invalid crash fault: \(issues.joined(separator: "; "))")
        logger.debug("▲ \(fault.identifier, privacy: .public)")
        #endif
        guard enabled, let crashlytics else { return }
        crashlytics.record(error: fault.error)
    }
}
