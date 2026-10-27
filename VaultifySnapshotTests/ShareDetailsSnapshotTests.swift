import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Vaultify

/// The share-details sheet, kept as render receipts (xcresult attachments) for
/// visual review across languages, appearances and contrast.
///
/// The live sheet needs iCloud and a second account to reach (its editor is
/// seeded from the recipient's grant), so the editor is rendered from a seeded
/// draft instead. The hand-over confirmation is the system alert, which a
/// snapshot cannot capture.
@MainActor
final class ShareDetailsSnapshotTests: XCTestCase {

    private static let itemID = "snapshot-share-details"

    // MARK: Full sheet (render receipts)

    func testSheetRenderReceipts() throws {
        let environment = try preparedEnvironment()
        let share = ItemShareRecord(itemId: Self.itemID, zoneName: "snapshot-zone",
                                    recipientLabel: "lan@example.com", grantId: "snapshot-grant",
                                    createdAtUnixMs: 1_704_067_200_000, fingerprintConfirmed: true)
        let live: [String: FieldCapability] = [
            "snap-user": .value(.shared), "snap-pass": .value(.shared), "snap-totp": .totp(.askEachTime),
        ]
        var edited = ShareCapabilityDraft(published: live)
        edited.select(.value(.none), for: "snap-pass")
        let states: [(String, ShareCapabilityDraft)] = [
            ("saved", ShareCapabilityDraft(published: live)),
            ("unsaved", edited),
        ]
        for language in ["vi", "en"] {
            for (dark, contrast) in [(false, false), (true, false), (false, true)] {
                for (name, draft) in states {
                    capture(ShareRecipientDetailSheet(share: share, draft: draft),
                            environment: environment, language: language, dark: dark,
                            highContrast: contrast, name: "sheet-\(name)")
                }
            }
        }
    }

    // MARK: Helpers

    private func preparedEnvironment() throws -> AppEnvironment {
        let environment = try makeSnapshotEnvironment()
        environment.session.adoptUnlocked(key: UITestConfiguration.fixtureKey, publishSharedSession: false)
        environment.repository.reload()
        if environment.repository.item(id: Self.itemID) == nil {
            let fixed = Date(timeIntervalSince1970: 1_704_067_200)
            try environment.repository.add(VaultItem(
                id: Self.itemID, category: .login, title: "Acme Login", folderId: nil,
                fields: [
                    DynamicField(id: "snap-user", label: "Username", kind: .username, value: "lan@acme.example"),
                    DynamicField(id: "snap-pass", label: "Password", kind: .password, value: "synthetic-value"),
                    DynamicField(id: "snap-totp", label: "One-time Code", kind: .totp, value: "JBSWY3DPEHPK3PXP"),
                ],
                createdAt: fixed, updatedAt: fixed))
        }
        return environment
    }

    private func applyAppearance(_ environment: AppEnvironment, language: String, dark: Bool) {
        environment.settings.preferredLanguage = language
        environment.theme.markAppearanceChosen()
        environment.theme.update { $0.theme = .builtin(dark ? .night : .day); $0.autoNight = .off }
    }

    private func capture(_ view: some View, environment: AppEnvironment, language: String,
                         dark: Bool, highContrast: Bool, name: String) {
        let oldLanguage = environment.settings.preferredLanguage
        let oldTheme = environment.theme.settings
        defer {
            environment.settings.preferredLanguage = oldLanguage
            environment.theme.update { $0 = oldTheme }
        }
        applyAppearance(environment, language: language, dark: dark)
        let subject = view
            .modifier(VaultRootEnvironment(env: environment))
            .environment(\.scenePhase, .active)
        let traits = UITraitCollection { traits in
            traits.displayScale = SnapshotEnvironment.displayScale
            traits.userInterfaceStyle = dark ? .dark : .light
            traits.accessibilityContrast = highContrast ? .high : .normal
        }
        // Drawn in the host's key window: off-window, the navigation bar drops
        // its toolbar items, and Apply is the part of this sheet worth seeing.
        let strategy: Snapshotting<AnyView, UIImage> = .image(
            drawHierarchyInKeyWindow: true, layout: .fixed(width: 390, height: 1100), traits: traits)
        let rendered = expectation(description: "Render \(name)")
        strategy.snapshot(AnyView(subject)).run { image in
            XCTAssertNotNil(image.pngData())
            let attachment = XCTAttachment(image: image)
            attachment.name = "\(name)-\(language)-\(dark ? "dark" : "light")\(highContrast ? "-high-contrast" : "")"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            rendered.fulfill()
        }
        wait(for: [rendered], timeout: 15)
    }
}
