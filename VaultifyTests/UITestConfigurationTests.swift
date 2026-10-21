import Foundation
import Testing
@testable import Vaultify

@Suite("UI-test launch configuration")
struct UITestConfigurationTests {
    @Test("Ordinary launches remain disabled")
    func ordinaryLaunchIsDisabled() throws {
        let configuration = try UITestConfiguration.parse(arguments: ["Vaultify"])
        #expect(configuration == .disabled)
    }

    @Test("Known fixture enables deterministic mode")
    func knownFixtureIsAccepted() throws {
        let configuration = try UITestConfiguration.parse(arguments: [
            "Vaultify",
            UITestConfiguration.launchFlag,
            UITestConfiguration.fixtureArgument,
            UITestConfiguration.Fixture.vaultEditSaveRelock.rawValue,
        ])
        #expect(configuration.fixture == .vaultEditSaveRelock)
        #expect(configuration.isEnabled)
    }

    @Test("Maestro launch arguments enable the same deterministic fixture")
    func maestroFixtureIsAccepted() throws {
        let configuration = try UITestConfiguration.parse(
            arguments: ["Vaultify", UITestConfiguration.maestroLaunchFlag],
            maestroFixture: UITestConfiguration.Fixture.vaultEditSaveRelock.rawValue
        )
        #expect(configuration.fixture == .vaultEditSaveRelock)
        #expect(configuration.isEnabled)
    }

    @Test("Missing fixture fails closed")
    func missingFixtureIsRejected() {
        #expect(throws: UITestConfiguration.ParseError.missingFixture) {
            try UITestConfiguration.parse(arguments: [
                "Vaultify",
                UITestConfiguration.launchFlag,
            ])
        }
    }

    @Test("Unknown fixture fails closed")
    func unknownFixtureIsRejected() {
        #expect(throws: UITestConfiguration.ParseError.unknownFixture("unknown")) {
            try UITestConfiguration.parse(arguments: [
                "Vaultify",
                UITestConfiguration.launchFlag,
                UITestConfiguration.fixtureArgument,
                "unknown",
            ])
        }
    }


    @Test("Maestro launch without a fixture fails closed")
    func maestroMissingFixtureIsRejected() {
        #expect(throws: UITestConfiguration.ParseError.missingFixture) {
            try UITestConfiguration.parse(arguments: [
                "Vaultify",
                UITestConfiguration.maestroLaunchFlag,
            ])
        }
    }

    @Test("Mixed native and Maestro launch contracts fail closed")
    func mixedLaunchContractsAreRejected() {
        #expect(throws: UITestConfiguration.ParseError.duplicateFixture) {
            try UITestConfiguration.parse(
                arguments: [
                    "Vaultify",
                    UITestConfiguration.launchFlag,
                    UITestConfiguration.fixtureArgument,
                    UITestConfiguration.Fixture.vaultEditSaveRelock.rawValue,
                    UITestConfiguration.maestroLaunchFlag,
                ],
                maestroFixture: UITestConfiguration.Fixture.vaultEditSaveRelock.rawValue
            )
        }
    }

    @Test("Injected settings defaults do not mutate the ordinary app domain")
    @MainActor
    func settingsDefaultsAreIsolated() throws {
        let standard = UserDefaults.standard
        let key = "auto_lock_timeout"
        let original = standard.object(forKey: key)
        standard.set(AutoLockTimeout.fiveMinutes.rawValue, forKey: key)
        defer {
            if let original {
                standard.set(original, forKey: key)
            } else {
                standard.removeObject(forKey: key)
            }
        }

        let suiteName = "com.bervion.vaultify.settings-test.\(UUID().uuidString)"
        let isolated = try #require(UserDefaults(suiteName: suiteName))
        defer { isolated.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: isolated, mirrorToSharedConfig: false)
        settings.autoLock = .immediate

        #expect(isolated.integer(forKey: key) == AutoLockTimeout.immediate.rawValue)
        #expect(standard.integer(forKey: key) == AutoLockTimeout.fiveMinutes.rawValue)
    }

    @Test("Test files are rooted outside production containers")
    func fileRootIsIsolated() {
        let root = UITestConfiguration.makeIsolatedFileRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(root.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(root.path.contains("/VaultifyTests/"))
        #expect(FileManager.default.fileExists(atPath: root.path))
        #expect(!root.path.hasPrefix(SharedConfig.containerURL.path))
    }

    @Test("UI-test composition does not write production preferences")
    @MainActor
    func appEnvironmentDefaultsAreIsolated() {
        let standard = UserDefaults.standard
        let protectedKeys = [
            "approval_recipient_device_id",
            "control_plane_migration_v1.capability_manifest.staging.done",
            "control_plane_migration_v1.domain_registry.staging.done",
            "control_plane_migration_v1.quick_view_signer_keyset.staging.done",
            "debug.looxTierOverride",
        ]
        let originals = Dictionary(uniqueKeysWithValues: protectedKeys.map {
            ($0, standard.object(forKey: $0))
        })
        protectedKeys.forEach { standard.removeObject(forKey: $0) }
        defer {
            for key in protectedKeys {
                if let original = originals[key] ?? nil {
                    standard.set(original, forKey: key)
                } else {
                    standard.removeObject(forKey: key)
                }
            }
        }

        let configuration = UITestConfiguration(fixture: .vaultEditSaveRelock)
        _ = TestAppEnvironment.make(uiTestConfiguration: configuration)

        for key in protectedKeys {
            #expect(standard.object(forKey: key) == nil, "Unexpected production write: \(key)")
        }
    }
}
