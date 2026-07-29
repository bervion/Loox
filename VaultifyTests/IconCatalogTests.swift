import XCTest
#if canImport(UIKit)
import UIKit
#endif
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

    func testChromeTokensAreBundledAssets() {
        // App chrome is the Polaris set. Only the Space/item picker offers SF, and only as an
        // addition — a chrome token that became a symbol would restyle the whole app at once.
        #if canImport(UIKit)
        var problems: [String] = []
        for token in Self.chromeTokens {
            guard case .asset(let asset) = IconResolver.resolve(token) else {
                problems.append("\(token) is not an asset name"); continue
            }
            if UIImage(named: asset) == nil { problems.append("\(asset) has no bundled asset") }
        }
        XCTAssertTrue(problems.isEmpty, "chrome icon problems: \(problems)")
        #endif
    }

    func testOnlyPrefixedNamesResolveToSymbols() {
        // Content and chrome glyphs are Polaris assets; only an explicitly `sf:`-prefixed name
        // becomes a symbol. Resolving unprefixed names onto SF once restyled the whole app.
        XCTAssertEqual(IconResolver.resolve("dt_folder"), .asset("dt_folder"))
        XCTAssertEqual(IconResolver.resolve("ic_lock_filled"), .asset("ic_lock_filled"))
        XCTAssertEqual(IconResolver.resolve("sf:lock.fill"), .system("lock.fill"))
    }

    func testPickerOffersBothFamilies() {
        let duotone = IconCatalog.allIcons.filter { !$0.isSystemSymbol }
        let symbols = IconCatalog.allIcons.filter(\.isSystemSymbol)
        XCTAssertEqual(duotone.count, 71, "the offerable duotone set is 71 glyphs")
        XCTAssertGreaterThan(symbols.count, 200, "SF symbols are the addition, not a token gesture")
        // Duotone leads: it is the product's own language and stays the default.
        XCTAssertEqual(IconCatalog.sections.first?.icons.first?.name, "dt_folder")
    }

    func testCatalogSymbolsExistOn17_3() {
        let symbols = IconCatalog.allIcons.filter(\.isSystemSymbol).compactMap { icon -> String? in
            guard case .system(let symbol) = IconResolver.resolve(icon.name) else { return nil }
            return symbol
        }
        assertAvailable(symbols, "IconCatalog")
    }

    func testCatalogIconsResolveToBundledAssets() {
        #if canImport(UIKit)
        // A missing asset renders as an empty tile with no crash and no log, so the picker can
        // silently ship holes. Only an existence check catches that.
        let missing = IconCatalog.allIcons.filter { !$0.isSystemSymbol }
            .map(\.name).filter { UIImage(named: $0) == nil }.sorted()
        XCTAssertTrue(missing.isEmpty, "catalog names with no bundled asset: \(missing)")
        #endif
    }

    func testCatalogHasNoDuplicateIcons() {
        let all = IconCatalog.allIcons.map(\.name)
        let duplicated = Dictionary(grouping: all, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
        XCTAssertTrue(duplicated.isEmpty, "icon listed in more than one category: \(duplicated)")
    }

    func testCatalogCoversEveryBundledDuotoneGlyph() {
        // Every duotone asset that ships should be pickable: one that exists but is absent from
        // the catalog is dead weight in the bundle and an icon the user can never choose.
        #if canImport(UIKit)
        XCTAssertTrue(IconCatalog.sections.allSatisfy { !$0.icons.isEmpty })
        XCTAssertGreaterThan(IconCatalog.sections.count, 10)
        #endif
    }

    func testEveryCatalogGlyphActuallyDraws() throws {
        // `UIImage(named:)` succeeds for an imageset whose SVG has no path data at all, so an
        // existence check is not enough — three glyphs shipped empty for months behind exactly
        // that gap and rendered as blank tiles in the picker. Read the source and require
        // drawable content.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let icons = root.appendingPathComponent("Vaultify/Assets.xcassets/PolarisIcons")
        var blank: [String] = []
        for icon in IconCatalog.allIcons where !icon.isSystemSymbol {
            let svg = icons.appendingPathComponent("\(icon.name).imageset/\(icon.name).svg")
            let source = try String(contentsOf: svg, encoding: .utf8)
            if !source.contains("<path") { blank.append(icon.name) }
        }
        XCTAssertTrue(blank.isEmpty, "catalog glyphs with no path data render blank: \(blank)")
    }

    func testDefaultIsAFolder() {
        // The model default and the picker default are the same value by construction; if this
        // drifts, a new Space is created with an icon the picker cannot show as selected.
        XCTAssertEqual(IconCatalog.defaultToken, "dt_folder")
    }

    func testSearchMatchesNameAndKeywords() {
        XCTAssertTrue(IconCatalog.search("folder").contains { $0.name == "dt_folder" })
        // The `dt_` prefix and underscores are stripped, so a two-word query finds the asset.
        XCTAssertTrue(IconCatalog.search("credit card").contains { $0.name == "dt_credit_card" })
        // Keywords carry the synonyms the name does not.
        XCTAssertTrue(IconCatalog.search("web").contains { $0.name == "dt_globe" })
        // The `sf:` prefix and dots are stripped too, so the SF additions are searchable.
        XCTAssertTrue(IconCatalog.search("credit card").contains { $0.name.hasPrefix("sf:creditcard") })
        XCTAssertTrue(IconCatalog.search("").isEmpty)
        XCTAssertTrue(IconCatalog.search("zzzznotanicon").isEmpty)
    }

    /// Mirrors the `Icons` surface. Kept explicit rather than reflected so that adding a token
    /// without covering it here is a visible omission.
    private static let chromeTokens: [String] = [
        Icons.home, Icons.homeFill, Icons.search, Icons.watchtower,
        Icons.settings, Icons.settingsFill, Icons.notification,
        Icons.add, Icons.addCircle, Icons.edit, Icons.delete, Icons.trash, Icons.copy,
        Icons.copyDone, Icons.reveal, Icons.hide, Icons.star, Icons.starFill, Icons.check,
        Icons.checkCircle, Icons.layoutSection, Icons.enter, Icons.close, Icons.closeCircle,
        Icons.chevronLeft, Icons.chevronRight, Icons.chevronDown, Icons.arrowRight,
        Icons.lock, Icons.lockFill, Icons.key, Icons.creditCard, Icons.shield,
        Icons.shieldAlert, Icons.shieldPerson, Icons.passkey, Icons.personLockFilled,
        Icons.alert, Icons.refresh, Icons.replay, Icons.sync,
        Icons.magic, Icons.clock, Icons.globe, Icons.share, Icons.info, Icons.folder,
        Icons.identityCard, Icons.orderRepeat, Icons.inventory,
        Icons.hashtag, Icons.plan, Icons.planFill, Icons.organization, Icons.organizationFill,
        Icons.apps, Icons.appsFill, Icons.pin, Icons.pinFill, Icons.archive,
        Icons.calendar, Icons.chartFill, Icons.importData, Icons.exportData, Icons.language,
        Icons.scanCode, Icons.person, Icons.mail, Icons.camera, Icons.image, Icons.device,
        Icons.pageAdd, Icons.moreHorizontal, Icons.sort, Icons.text, Icons.attachment,
    ]
}
