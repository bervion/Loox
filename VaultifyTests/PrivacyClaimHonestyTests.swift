import XCTest
@testable import Vaultify

/// The in-app equivalent of the marketing site's claims gate. The About page and the
/// settings panes make absolute privacy claims in three languages; nothing else in the
/// project checks them against what the binary actually does, and a claim that drifts
/// out of true is invisible until a reviewer or a regulator reads it.
///
/// The claims are source-scanned rather than rendered: they are `Text` literals inside
/// view bodies, so there is no value to assert without hosting the view, and a phrase
/// reintroduced anywhere in the app is exactly the failure worth catching.
@MainActor
final class PrivacyClaimHonestyTests: XCTestCase {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: Self.repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Comment lines are dropped so a comment may still quote a retired claim and say why
    /// it went — the gate is about what the app SHOWS, and losing that history to satisfy
    /// a string search would be the wrong trade.
    private func swiftSources() throws -> [(path: String, text: String)] {
        var found: [(path: String, text: String)] = []
        for directory in ["Vaultify", "VaultifyCore"] {
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

    /// Every phrase here shipped at some point and was false of the shipping build.
    /// Analytics is opt-in and crash diagnostics opt-out (`SettingsStore`), and the app
    /// reaches CloudKit, the sharing relay, Quick View, the entitlement service, the
    /// breach range API and Google's favicon endpoint.
    func testRetiredClaimsAreNotInTheApp() throws {
        let forbidden = [
            "collects no analytics",
            "Nothing is sent to a server",
            "Zero backend",
            "The only network request",
            "No servers holding your vault",
            "Everything is sealed with AES-256",
        ]
        var offenders: [String] = []
        for file in try swiftSources() {
            for phrase in forbidden where file.text.contains(phrase) {
                offenders.append("\(URL(fileURLWithPath: file.path).lastPathComponent): \(phrase)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "privacy claims that the shipping build contradicts: \(offenders)")
    }

    /// The About copy names the defaults out loud, so the defaults are what make it true.
    /// Flipping either one without rewriting the sentence turns the page into a false
    /// statement, which is the whole failure this pairing exists to prevent.
    func testAboutCopyMatchesShippingConsentDefaults() {
        let suite = "privacy-claim-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, mirrorToSharedConfig: false)

        XCTAssertFalse(settings.analyticsEnabled,
                       "About says analytics stay off unless the user turns them on")
        XCTAssertTrue(settings.crashReportingEnabled,
                      "About says crash diagnostics are on and can be turned off")
    }

    /// `termsURL` / `privacyURL` used to appear on the purchase sheet alone, so a user who
    /// never opened it had no in-app route to either policy.
    func testAboutLinksToBothPolicies() throws {
        let about = try source("Vaultify/Features/Settings/AboutView.swift")
        XCTAssertTrue(about.contains("LooxMembership.privacyURL"), "About must link the privacy policy")
        XCTAssertTrue(about.contains("LooxMembership.termsURL"), "About must link the terms")
    }

    /// The breach check is the only setting on those panes that talks to a third party, and
    /// it must say how. On macOS it used to share the website-icon footer, which told the
    /// user the breach check goes to Google.
    func testBreachToggleCarriesItsOwnDisclosure() throws {
        let disclosure = "Uses k-anonymity."
        for pane in ["Vaultify/Features/Settings/SecuritySettingsView.swift",
                     "Vaultify/Features/Settings/MacSettingsView.swift",
                     "Vaultify/Features/Watchtower/WatchtowerScreen.swift"] {
            XCTAssertTrue(try source(pane).contains(disclosure),
                          "\(pane) offers the breach toggle without disclosing what it sends")
        }
    }

    /// Naming the processor is the disclosure. Keep it wherever the toggle lives.
    func testFaviconDisclosureNamesGoogle() throws {
        for pane in ["Vaultify/Features/Settings/GeneralSettingsView.swift",
                     "Vaultify/Features/Settings/MacSettingsView.swift"] {
            XCTAssertTrue(try source(pane).contains("Uses Google to fetch site icons"),
                          "\(pane) toggles website icons without naming Google")
        }
    }
}
