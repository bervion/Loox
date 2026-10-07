import SnapshotTesting
import SwiftUI
import UIKit
import XCTest
@testable import Vaultify

/// Native render receipts for newly composed feature roots. Images are kept
/// as xcresult attachments for visual review, not auto-approved pixel baselines.
@MainActor
final class PrivateEmailMemberSnapshotTests: XCTestCase {
    func testSmallEnglishLight() throws {
        try captureMatrix(width: 375, height: 812, language: "en", dark: false, accessible: false)
    }

    func testSmallVietnameseLight() throws {
        try captureMatrix(width: 375, height: 812, language: "vi", dark: false, accessible: false)
    }

    func testLargeVietnameseDark() throws {
        try captureMatrix(width: 430, height: 932, language: "vi", dark: true, accessible: false)
    }

    func testSmallVietnameseAccessibilityDark() throws {
        try captureMatrix(width: 375, height: 812, language: "vi", dark: true, accessible: true)
    }

    private func captureMatrix(width: CGFloat, height: CGFloat, language: String,
                               dark: Bool, accessible: Bool) throws {
        let environment = try makeSnapshotEnvironment()
        environment.session.adoptUnlocked(key: UITestConfiguration.fixtureKey, publishSharedSession: false)
        environment.repository.reload()
        try UITestFixtures.installPrivateEmailMemberUX(store: environment.repository.store,
                                                       repository: environment.repository)
        let oldLanguage = environment.settings.preferredLanguage
        let oldTheme = environment.theme.settings
        defer {
            environment.settings.preferredLanguage = oldLanguage
            environment.theme.update { $0 = oldTheme }
        }
        environment.settings.preferredLanguage = language
        environment.theme.markAppearanceChosen()
        environment.theme.update { $0.theme = .builtin(dark ? .night : .day); $0.autoNight = .off }
        let persona = try XCTUnwrap(environment.repository.activePersona)
        let link = try XCTUnwrap(environment.repository.linkedServices(for: persona.id).first)
        XCTAssertEqual(environment.repository.linkedServices(for: persona.id).count, 3)
        let screens: [(String, AnyView)] = [
            ("overview", AnyView(PersonaAliasesScreen())),
            ("services", AnyView(AliasLinkedServicesScreen(personaID: persona.id))),
            ("service-detail", AnyView(AliasLinkedServiceDetailScreen(link: link))),
            ("alias", AnyView(AliasDetailScreen(aliasID: UITestFixtures.reusableAliasID))),
            ("inbox", AnyView(ForwardingInboxDetailScreen(inboxID: UITestFixtures.inboxID))),
            ("composer", AnyView(AliasEditorSheet(persona: persona))),
            ("member", AnyView(LooxHubScreen())),
            ("links", AnyView(ShareLinksScreen())),
            ("browser", AnyView(SendToBrowserScreen())),
            ("family", AnyView(FamilyScreen())),
        ]
        for (name, screen) in screens {
            let subject = NavigationStack { screen }
                .modifier(VaultRootEnvironment(env: environment))
                .environment(\.scenePhase, .active)
                .environment(\.dynamicTypeSize, accessible ? .accessibility3 : .large)
            let rendered = expectation(description: "Render \(name)")
            let traits = UITraitCollection { traits in
                traits.displayScale = SnapshotEnvironment.displayScale
                traits.accessibilityContrast = accessible ? .high : .normal
                traits.userInterfaceStyle = dark ? .dark : .light
            }
            let strategy: Snapshotting<AnyView, UIImage> = .image(
                layout: .fixed(width: width, height: height), traits: traits)
            strategy.snapshot(AnyView(subject)).run { image in
                XCTAssertEqual(image.size.width, width, accuracy: 0.5)
                XCTAssertEqual(image.size.height, height, accuracy: 0.5)
                XCTAssertNotNil(image.pngData())
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(name)-\(Int(width))-\(language)-\(dark ? "dark" : "light")\(accessible ? "-accessibility" : "")"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                rendered.fulfill()
            }
            wait(for: [rendered], timeout: 15)
        }
    }
}
