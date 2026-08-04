import XCTest
@testable import Vaultify

/// The control plane (Approval Mode sharing) and the secret plane (vault-item
/// iCloud sync) are separate consents. The invariant held across every call
/// site but nothing tested it, so a refactor that "tidied up" two adjacent
/// booleans into one would have shipped: enabling sharing would start uploading
/// vault ciphertext, or turning sync off would silently break someone else's
/// approval requests.
@MainActor
final class SyncOptInContractTests: XCTestCase {

    // MARK: Nothing syncs until the user says so

    func testBothSyncPlanesStartOff() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)

        XCTAssertFalse(settings.iCloudSyncEnabled)
        XCTAssertFalse(settings.approvalModeEnabled)
        // The artifact plane is not wired into the live push/pull yet; it must
        // not be reachable by default before its convergence story exists.
        XCTAssertFalse(settings.artifactSyncEnabled)
    }

    // MARK: Control plane never implies the secret plane

    func testEnablingApprovalModeNeverEnablesVaultSync() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)

        settings.approvalModeEnabled = true

        XCTAssertFalse(settings.iCloudSyncEnabled,
                       "Sharing a login for approval must never start uploading the vault")
        XCTAssertNil(defaults.object(forKey: "icloud_sync_enabled"),
                     "Approval Mode must not answer the vault-sync question at all")
    }

    func testDisablingApprovalModeLeavesVaultSyncOn() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        settings.iCloudSyncEnabled = true
        settings.approvalModeEnabled = true

        settings.approvalModeEnabled = false

        XCTAssertTrue(settings.iCloudSyncEnabled)
    }

    // MARK: Secret plane never gates the control plane

    func testEnablingVaultSyncNeverEnablesApprovalMode() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)

        settings.iCloudSyncEnabled = true

        XCTAssertFalse(settings.approvalModeEnabled)
        XCTAssertNil(defaults.object(forKey: "approval_mode_enabled"))
    }

    func testTurningVaultSyncOffLeavesApprovalModeRunning() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)
        settings.approvalModeEnabled = true
        settings.iCloudSyncEnabled = true

        settings.iCloudSyncEnabled = false

        // The approval push pipeline is gated on its OWN flag; stopping vault
        // uploads must not strand a request the other side is waiting on.
        XCTAssertTrue(settings.approvalModeEnabled)
        XCTAssertTrue(defaults.bool(forKey: "approval_mode_enabled"))
    }

    func testEachPlanePersistsUnderItsOwnKey() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)

        settings.iCloudSyncEnabled = true
        settings.approvalModeEnabled = false

        // Two keys, two answers. A shared key is how the two planes would fuse.
        XCTAssertEqual(defaults.object(forKey: "icloud_sync_enabled") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "approval_mode_enabled") as? Bool, false)
    }

    func testAStoredApprovalChoiceSurvivesRelaunchWithoutTouchingSync() throws {
        let (defaults, suite) = try freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        SettingsStore(defaults: defaults, mirrorToSharedConfig: false).approvalModeEnabled = true

        let relaunched = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)

        XCTAssertTrue(relaunched.approvalModeEnabled)
        XCTAssertFalse(relaunched.iCloudSyncEnabled)
    }

    // MARK: Erase closes both planes

    func testEraseOnThisDeviceTurnsBothPlanesOff() {
        let env = TestAppEnvironment.make()
        env.settings.iCloudSyncEnabled = true
        env.settings.approvalModeEnabled = true

        env.eraseThisDevice()

        // The vault this device syncs and shares no longer exists here. Leaving
        // either flag on would have the next unlock re-arm a plane for a vault
        // the user just destroyed.
        XCTAssertFalse(env.settings.iCloudSyncEnabled)
        XCTAssertFalse(env.settings.approvalModeEnabled)
    }

    func testEraseEverywhereTurnsBothPlanesOff() {
        let env = TestAppEnvironment.make()
        env.settings.iCloudSyncEnabled = true
        env.settings.approvalModeEnabled = true

        // The tail of "erase everywhere", once the remote teardown reported.
        env.finishErase(retainingLinks: [])

        XCTAssertFalse(env.settings.iCloudSyncEnabled)
        XCTAssertFalse(env.settings.approvalModeEnabled)
    }

    // MARK: Helpers

    private func freshDefaults() throws -> (UserDefaults, String) {
        let suite = "com.bervion.vaultify.sync-contract-test.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
