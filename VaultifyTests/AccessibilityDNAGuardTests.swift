import XCTest
@testable import Vaultify

/// Design-DNA and accessibility invariants that only exist as view-body syntax, plus the
/// one storage invariant left behind by deleting the app-level Reduce Motion setting.
///
/// Source-scanned rather than rendered, for the same reason `PrivacyClaimHonestyTests`
/// scans: these are modifiers inside `View` bodies, so there is no value to assert without
/// hosting the view, and the failure worth catching is the modifier being dropped anywhere
/// in the app rather than in one screen.
@MainActor
final class AccessibilityDNAGuardTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Comment lines are dropped so a comment may still quote a retired pattern and explain
    /// why it went — the gate is about what the app COMPILES, not about its history.
    private func swiftSources(_ directories: [String] = ["Vaultify", "VaultifyCore", "VaultifyAutoFill"])
        throws -> [(path: String, text: String)] {
        var found: [(String, String)] = []
        for directory in directories {
            let root = Self.repoRoot.appendingPathComponent(directory)
            guard let walker = FileManager.default.enumerator(at: root,
                                                              includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")
                found.append((url.path, code))
            }
        }
        return found
    }

    private func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let sub = Range(match.range(at: index), in: text) else { return "" }
                return String(text[sub])
            }
        }
    }

    // MARK: "Untitled" fallback

    /// `Text(item.title.isEmpty ? "Untitled" : item.title)` resolves to the `Text(String)`
    /// overload, which renders VERBATIM: the catalog is never consulted and a VI or JA user
    /// reads the English word. Every fallback must go through `appString`.
    func testUntitledFallbackAlwaysGoesThroughTheCatalog() throws {
        var offenders: [String] = []
        for file in try swiftSources() {
            let text = file.text
            var search = text.startIndex..<text.endIndex
            while let found = text.range(of: "\"Untitled", range: search) {
                let prefixStart = text.index(found.lowerBound,
                                             offsetBy: -11,
                                             limitedBy: text.startIndex) ?? text.startIndex
                if !text[prefixStart..<found.lowerBound].hasSuffix("appString(") {
                    offenders.append(URL(fileURLWithPath: file.path).lastPathComponent)
                }
                search = found.upperBound..<text.endIndex
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "Raw \"Untitled\" literal (ships English into VI/JA) in: \(Set(offenders).sorted())")
    }

    /// The fallback the previous test forces every call site onto must actually exist in
    /// every shipped language, or the guard just moves the English leak one layer down.
    func testUntitledKeysShipVietnameseAndJapanese() throws {
        let data = try Data(contentsOf: Self.repoRoot.appendingPathComponent("Vaultify/Localizable.xcstrings"))
        let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = catalog?["strings"] as? [String: Any] ?? [:]
        for key in ["Untitled", "Untitled item"] {
            let entry = strings[key] as? [String: Any]
            let localizations = entry?["localizations"] as? [String: Any] ?? [:]
            for language in ["vi", "ja"] {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String ?? ""
                XCTAssertFalse(value.isEmpty, "Localizable.xcstrings is missing \(language) for \"\(key)\"")
                XCTAssertNotEqual(value, key, "\(language) translation for \"\(key)\" is still the English source")
            }
        }
    }

    // MARK: Selection is announced

    /// A selection ring plus a check glyph is invisible to VoiceOver (`VaultIcon` is
    /// accessibility-hidden by design), so the theme pickers must carry `.isSelected`.
    func testThemePickersAnnounceSelectionToVoiceOver() throws {
        for path in ["Vaultify/Features/Onboarding/ChooseThemeView.swift",
                     "Vaultify/Features/Settings/Appearance/AppearanceSettingsView.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("accessibilityAddTraits") && text.contains(".isSelected"),
                          "\(path) draws a selected state VoiceOver cannot read")
        }
    }

    // MARK: Reduce Motion / Reduce Transparency

    /// `ThemedToggleStyle` is applied app-wide (`VaultRootEnvironment`), so an ungated
    /// spring there is every switch in the app ignoring Reduce Motion.
    func testAppWideToggleStyleGatesItsAnimation() throws {
        let text = try source("Vaultify/DesignSystem/Components/ThemedToggleStyle.swift")
        XCTAssertTrue(text.contains("accessibilityReduceMotion"),
                      "ThemedToggleStyle animates without reading Reduce Motion")
        XCTAssertTrue(text.contains(".vault(Motion.spring, reduceMotion: reduceMotion)"),
                      "ThemedToggleStyle should animate through the Motion token + reduceMotion gate")
    }

    /// Both floating surfaces sit over content, which is exactly what Reduce Transparency
    /// exists to make readable.
    func testFloatingSurfacesHaveAnOpaqueFallback() throws {
        for path in ["Vaultify/Features/Components/CopyToastOverlay.swift",
                     "Vaultify/Features/ItemEditor/EditorFieldRow.swift"] {
            let text = try source(path)
            XCTAssertTrue(text.contains("accessibilityReduceTransparency"),
                          "\(path) never reads Reduce Transparency")
            XCTAssertTrue(text.contains("surfaceFloatingSolid"),
                          "\(path) has no opaque surface for Reduce Transparency")
        }
    }

    /// `Color.primary` is the SYSTEM label color: on a themed floating surface it ignores
    /// the active theme entirely.
    func testGenerateChipHairlineIsThemed() throws {
        let text = try source("Vaultify/Features/ItemEditor/EditorFieldRow.swift")
        XCTAssertFalse(text.contains("Color.primary.opacity"),
                       "EditorFieldRow paints a raw system-label hairline on a themed surface")
    }

    // MARK: minimumScaleFactor floor

    /// The DNA standard puts the shrink-to-fit floor at 0.7: below it, text stops being
    /// legible and the layout should reflow instead.
    ///
    /// Two deliberate exceptions, both non-Dynamic-Type surfaces holding ONE secret whose
    /// alternative to shrinking is truncation:
    /// - `LargeTypeView` renders a single character per cell at a size chosen to be read
    ///   across a room.
    /// - `EmergencyKitPDFPage` draws onto a fixed printed page, not a device screen.
    func testMinimumScaleFactorRespectsTheDNAFloor() throws {
        let exempt = ["LargeTypeView.swift", "EmergencyKitPDFPage.swift"]
        var offenders: [String] = []
        for file in try swiftSources(["Vaultify"]) {
            let name = URL(fileURLWithPath: file.path).lastPathComponent
            guard !exempt.contains(name) else { continue }
            for match in matches(#"minimumScaleFactor\(([0-9.]+)\)"#, in: file.text) {
                guard let value = Double(match[1]) else { continue }
                if value < 0.7 { offenders.append("\(name): \(match[1])") }
            }
        }
        XCTAssertTrue(offenders.isEmpty, "minimumScaleFactor below the 0.7 floor in: \(offenders.sorted())")
    }

    // MARK: The deleted app-level Reduce Motion setting

    /// Motion has exactly one source of truth, the system setting. A second in-app copy of
    /// Settings > Accessibility > Motion could only disagree with it, and the one that
    /// shipped reached nothing but the disabled wallpaper engine.
    func testNoAppLevelReduceMotionSetting() throws {
        let settings = try source("VaultifyCore/Theme/ThemeSettings.swift")
        XCTAssertFalse(settings.contains("var reduceMotion: Bool"),
                       "ThemeSettings should not store a motion preference")
        let store = try source("Vaultify/DesignSystem/Theme/ThemeStore.swift")
        XCTAssertFalse(store.contains("setReduceMotion"), "ThemeStore should not write a motion preference")
        let appearance = try source("Vaultify/Features/Settings/Appearance/AppearanceSettingsView.swift")
        XCTAssertFalse(appearance.contains("Text(\"Reduce Motion\")"),
                       "Appearance settings should not offer a second Reduce Motion switch")
    }

    /// Installs that already persisted the retired key must keep loading: the App Group JSON
    /// is the app's appearance, and a decode failure there resets every theme choice.
    func testStoredSettingsWithTheRetiredMotionKeyStillDecode() throws {
        var settings = ThemeSettings.default
        settings.theme = .builtin(.night)
        settings.fontScale = .large

        // Re-create what a pre-removal install actually wrote, without hard-coding the
        // enum wire format: encode today's model, then put the retired key back.
        let encoded = try JSONEncoder().encode(settings)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["reduceMotion"] = true
        let legacy = try JSONSerialization.data(withJSONObject: object)

        XCTAssertEqual(try JSONDecoder().decode(ThemeSettings.self, from: legacy), settings)
    }
}
