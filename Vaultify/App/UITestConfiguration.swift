import Foundation

/// Explicit, fail-closed configuration for deterministic UI-test launches.
///
/// The parser and fixture credentials are compiled only into Debug products.
/// Release products always resolve to `.disabled`, even if matching process
/// arguments are supplied.
nonisolated struct UITestConfiguration: Equatable, Sendable {
    #if DEBUG
    enum Fixture: String, Equatable, Sendable {
        case vaultEditSaveRelock = "vault-edit-save-relock"
    }

    let fixture: Fixture?

    var isEnabled: Bool { fixture != nil }

    static let disabled = UITestConfiguration(fixture: nil)
    #else
    var isEnabled: Bool { false }

    static let disabled = UITestConfiguration()

    private init() {}
    #endif

    static var current: UITestConfiguration {
        #if DEBUG
        do {
            return try parse(
                arguments: ProcessInfo.processInfo.arguments,
                maestroFixture: UserDefaults.standard.string(forKey: maestroFixtureArgument)
            )
        } catch {
            preconditionFailure("Invalid UI-test launch configuration: \(error)")
        }
        #else
        return .disabled
        #endif
    }

    #if DEBUG
    enum ParseError: Error, Equatable {
        case missingFixture
        case duplicateFixture
        case unknownFixture(String)
    }

    static let launchFlag = "-ui-testing"
    static let fixtureArgument = "-ui-test-fixture"
    static let maestroLaunchFlag = "ui-testing"
    static let maestroFixtureArgument = "ui-test-fixture"
    static let fixturePassword = "vaultify-ui-test-password"
    static let fixtureKey: [UInt8] = Array(0..<32)
    static let settingsDefaultsSuite = "com.bervion.vaultify.ui-testing"

    static func makeIsolatedSettingsDefaults() -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: settingsDefaultsSuite) else {
            preconditionFailure("Unable to create isolated UI-test preferences")
        }
        defaults.removePersistentDomain(forName: settingsDefaultsSuite)
        return defaults
    }

    static func makeIsolatedFileRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "VaultifyTests", directoryHint: .isDirectory)
            .appending(path: "\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
            return root
        } catch {
            preconditionFailure("Unable to create isolated test directory: \(error)")
        }
    }

    static func parse(
        arguments: [String],
        maestroFixture: String? = nil
    ) throws -> UITestConfiguration {
        let nativeLaunch = arguments.contains(launchFlag)
        let maestroLaunch = arguments.contains(maestroLaunchFlag)
        guard nativeLaunch || maestroLaunch else { return .disabled }

        var fixtureValues: [String] = []
        if nativeLaunch {
            let fixtureIndexes = arguments.indices.filter { arguments[$0] == fixtureArgument }
            guard fixtureIndexes.count <= 1 else { throw ParseError.duplicateFixture }
            guard let index = fixtureIndexes.first, arguments.indices.contains(index + 1) else {
                throw ParseError.missingFixture
            }
            fixtureValues.append(arguments[index + 1])
        }

        if maestroLaunch {
            guard let maestroFixture, !maestroFixture.isEmpty else {
                throw ParseError.missingFixture
            }
            fixtureValues.append(maestroFixture)
        }

        guard fixtureValues.count == 1 else { throw ParseError.duplicateFixture }
        let rawValue = fixtureValues[0]
        guard let fixture = Fixture(rawValue: rawValue) else {
            throw ParseError.unknownFixture(rawValue)
        }
        return UITestConfiguration(fixture: fixture)
    }
    #endif
}
