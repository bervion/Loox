import XCTest
@testable import Vaultify

/// Guards the icon system's one silent failure mode: an SF Symbol that does not exist on the
/// deployment floor compiles without a warning and renders as an empty box at runtime. Nothing
/// else in the project catches that — there is no snapshot coverage of an icon and no analytics
/// event carries one.
final class IconCatalogTests: XCTestCase {

    /// Symbol names shipped on iOS 17.3, loaded from the bundled fixture. The test bundle runs
    /// on whatever simulator CI provides (currently far newer than 17.3), so asking the running
    /// SDK whether a symbol exists proves nothing about the floor — only this list does.
    private static let availableOn17_3: Set<String> = {
        guard let url = Bundle(for: IconCatalogTests.self)
            .url(forResource: "sf-symbols-ios-17-3", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return Set(text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") })
    }()

    private func assertAvailable(_ symbols: [String], _ source: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let unavailable = symbols.filter { !Self.availableOn17_3.contains($0) }.sorted()
        XCTAssertTrue(unavailable.isEmpty,
                      "\(source) uses SF Symbols missing on iOS 17.3 (they render blank): \(unavailable)",
                      file: file, line: line)
    }

    func testFixtureLoaded() {
        // A silently empty fixture would make every other assertion in this file vacuous.
        XCTAssertGreaterThan(Self.availableOn17_3.count, 6000,
                             "SF Symbol availability fixture failed to load")
    }

    func testPickerCatalogSymbolsExistOn17_3() {
        assertAvailable(IconCatalog.allIcons.map(\.symbol), "IconCatalog")
    }

    func testChromeTokensExistOn17_3() {
        // Tokens are stored `sf:`-prefixed, so resolve them the way the renderer does.
        let symbols = Self.chromeTokens.compactMap { name -> String? in
            guard case .system(let symbol) = IconResolver.resolve(name) else { return nil }
            return symbol
        }
        XCTAssertEqual(symbols.count, Self.chromeTokens.count,
                       "every Icons token should resolve to an SF Symbol")
        assertAvailable(symbols, "Icons")
    }

    func testLegacyMapTargetsExistOn17_3() {
        assertAvailable(Array(LegacyIconMap.systemName.values), "LegacyIconMap")
    }

    func testCatalogTokensResolveToTheirSymbol() {
        // The renderer takes an icon NAME, and a bare SF symbol name is not one: it resolves as
        // an asset name and draws nothing — no crash, no log, just an empty tile. Every catalog
        // entry must therefore be handed to the renderer as its `token`, never its `symbol`.
        for icon in IconCatalog.allIcons {
            XCTAssertEqual(IconResolver.resolve(icon.token), .system(icon.symbol),
                           "catalog token \(icon.token) should resolve to \(icon.symbol)")
        }
        XCTAssertEqual(IconResolver.resolve("folder.fill"), .asset("folder.fill"),
                       "a bare symbol name must NOT be mistaken for a resolvable icon name")
    }

    func testCatalogHasNoDuplicateSymbols() {
        let all = IconCatalog.allIcons.map(\.symbol)
        let duplicated = Dictionary(grouping: all, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        XCTAssertTrue(duplicated.isEmpty, "symbol listed in more than one category: \(duplicated)")
    }

    func testCatalogIsSubstantial() {
        // The picker this replaced offered 66 icons; a truncated regeneration must not pass.
        XCTAssertGreaterThan(IconCatalog.allIcons.count, 200)
        XCTAssertGreaterThan(IconCatalog.sections.count, 10)
        XCTAssertTrue(IconCatalog.sections.allSatisfy { !$0.icons.isEmpty })
    }

    func testDefaultTokenIsAFolder() {
        // The model default and the picker default are the same value by construction; if this
        // drifts, a new Space is created with an icon the picker cannot show as selected.
        XCTAssertEqual(IconCatalog.defaultToken, IconResolver.token("folder.fill"))
    }

    func testSearchMatchesNameAndKeywords() {
        XCTAssertTrue(IconCatalog.search("folder").contains { $0.symbol == "folder.fill" })
        // Dots and spaces are equivalent, so a two-word query finds a run-together symbol name.
        XCTAssertTrue(IconCatalog.search("credit card").contains { $0.symbol.hasPrefix("creditcard") })
        XCTAssertTrue(IconCatalog.search("").isEmpty)
        XCTAssertTrue(IconCatalog.search("zzzznotasymbol").isEmpty)
    }

    /// Mirrors the `Icons` surface. Kept explicit rather than reflected so that adding a token
    /// without covering it here is a visible omission.
    private static let chromeTokens: [String] = [
        Icons.home, Icons.homeFill, Icons.search, Icons.watchtower, Icons.securityTab,
        Icons.securityTabFill, Icons.settings, Icons.settingsFill, Icons.notification,
        Icons.add, Icons.addCircle, Icons.edit, Icons.delete, Icons.trash, Icons.copy,
        Icons.copyDone, Icons.reveal, Icons.hide, Icons.star, Icons.starFill, Icons.check,
        Icons.checkCircle, Icons.layoutSection, Icons.enter, Icons.close, Icons.closeCircle,
        Icons.chevronLeft, Icons.chevronRight, Icons.chevronDown, Icons.arrowRight,
        Icons.lock, Icons.lockFill, Icons.key, Icons.creditCard, Icons.shield,
        Icons.shieldAlert, Icons.shieldPerson, Icons.passkey, Icons.personLockFilled,
        Icons.identityShielded, Icons.alert, Icons.refresh, Icons.replay, Icons.sync,
        Icons.magic, Icons.clock, Icons.globe, Icons.share, Icons.info, Icons.folder,
        Icons.identityCard, Icons.orderRepeat, Icons.recentlyUsed, Icons.inventory,
        Icons.hashtag, Icons.plan, Icons.planFill, Icons.organization, Icons.organizationFill,
        Icons.apps, Icons.appsFill, Icons.appearance, Icons.pin, Icons.pinFill, Icons.archive,
        Icons.calendar, Icons.chartFill, Icons.importData, Icons.exportData, Icons.language,
        Icons.scanCode, Icons.person, Icons.mail, Icons.camera, Icons.image, Icons.device,
        Icons.pageAdd, Icons.moreHorizontal, Icons.reduceMotion, Icons.pause,
    ]
}
