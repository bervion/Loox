import XCTest
@testable import Vaultify

/// Every consent default the app ships with had zero automated coverage while
/// deciding, on a fresh install, what leaves the device before the user has
/// answered anything. A default here is a privacy decision, so it is pinned as
/// a value, not as a comment.
@MainActor
final class SettingsStoreTests: XCTestCase {

    // MARK: Ship defaults

    func testFreshInstallSendsNoUsageStatistics() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Opt-IN. A password manager must not be measuring the very first
        // session on the strength of a default the user never saw.
        XCTAssertFalse(SettingsStore(defaults: defaults, mirrorToSharedConfig: false).analyticsEnabled)
    }

    func testFreshInstallKeepsCrashDiagnosticsOn() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Deliberately NOT moved with analytics: a crash report carries no
        // vault content and is the only thing that explains a lost session.
        XCTAssertTrue(SettingsStore(defaults: defaults, mirrorToSharedConfig: false).crashReportingEnabled)
    }

    func testFreshInstallShowsWebsiteIcons() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        // ON by design, with the third-party lookup disclosed in the settings
        // footer. Flipping this to off is a product decision, not a cleanup.
        XCTAssertTrue(SettingsStore(defaults: defaults, mirrorToSharedConfig: false).showWebsiteIcons)
    }

    func testFreshInstallUploadsNothingToICloud() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(SettingsStore(defaults: defaults, mirrorToSharedConfig: false).iCloudSyncEnabled)
    }

    // MARK: The default is a fallback, not a stored value

    func testReadingDefaultsPersistsNothing() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        _ = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)

        // Construction must not freeze today's answer onto disk: an install
        // that never touched the switch has to follow the shipped default,
        // which is what makes a later consent change reach existing users.
        XCTAssertNil(defaults.object(forKey: "analytics_enabled"))
        XCTAssertNil(defaults.object(forKey: "crash_reporting_enabled"))
        XCTAssertNil(defaults.object(forKey: "show_website_icons"))
        XCTAssertNil(defaults.object(forKey: "icloud_sync_enabled"))
    }

    func testAnExplicitAnswerAlwaysWinsOverTheDefault() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "analytics_enabled")
        XCTAssertTrue(SettingsStore(defaults: defaults, mirrorToSharedConfig: false).analyticsEnabled,
                      "A user who opted in must stay opted in across launches")

        defaults.set(false, forKey: "crash_reporting_enabled")
        XCTAssertFalse(SettingsStore(defaults: defaults, mirrorToSharedConfig: false).crashReportingEnabled,
                       "A user who opted out must stay opted out across launches")
    }

    // MARK: Bootstrap agrees with the settings screen

    /// `AnalyticsEngine` and `CrashReporter` read consent through the static
    /// accessors at launch, before any `SettingsStore` exists. A fallback that
    /// disagreed with the property would leave collection ON while the toggle
    /// rendered OFF, and nothing would ever call `setEnabled` to correct it —
    /// no `didSet` fires for a switch the user never touched.
    func testLaunchTimeConsentReadsMatchTheStoredDefaults() throws {
        let standard = UserDefaults.standard
        let analyticsKey = "analytics_enabled"
        let crashKey = "crash_reporting_enabled"
        let savedAnalytics = standard.object(forKey: analyticsKey)
        let savedCrash = standard.object(forKey: crashKey)
        defer {
            restore(savedAnalytics, forKey: analyticsKey, in: standard)
            restore(savedCrash, forKey: crashKey, in: standard)
        }
        standard.removeObject(forKey: analyticsKey)
        standard.removeObject(forKey: crashKey)

        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)

        XCTAssertEqual(SettingsStore.isAnalyticsEnabled(), settings.analyticsEnabled)
        XCTAssertEqual(SettingsStore.isCrashReportingEnabled(), settings.crashReportingEnabled)
        XCTAssertFalse(SettingsStore.isAnalyticsEnabled())
        XCTAssertTrue(SettingsStore.isCrashReportingEnabled())
    }

    // MARK: The two telemetry consents are independent

    func testTurningAnalyticsOffLeavesCrashDiagnosticsAlone() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)

        settings.analyticsEnabled = true
        settings.analyticsEnabled = false

        XCTAssertTrue(settings.crashReportingEnabled)
        XCTAssertNil(defaults.object(forKey: "crash_reporting_enabled"),
                     "Declining usage statistics must not answer the crash question for the user")
    }

    func testTurningCrashDiagnosticsOffLeavesAnalyticsAlone() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        settings.analyticsEnabled = true

        settings.crashReportingEnabled = false

        XCTAssertTrue(settings.analyticsEnabled)
        XCTAssertTrue(defaults.bool(forKey: "analytics_enabled"))
    }

    func testEachConsentPersistsUnderItsOwnKey() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)

        settings.analyticsEnabled = true
        settings.crashReportingEnabled = false

        // Distinct keys are what keeps the two answers from silently merging.
        XCTAssertEqual(defaults.object(forKey: "analytics_enabled") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "crash_reporting_enabled") as? Bool, false)
    }

    // MARK: Helpers

    private func freshDefaults() throws -> (UserDefaults, String) {
        let suite = "com.bervion.vaultify.settings-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
