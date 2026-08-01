import XCTest
@testable import Vaultify

/// Pure logic of the browse-list sort vocabulary: key + direction ordering,
/// the legacy `.updated` default, and the month-year sectioning contract.
@MainActor
final class VaultSortTests: XCTestCase {

    private let jan = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
    private let feb = Date(timeIntervalSince1970: 1_706_745_600) // 2024-02-01
    private let mar = Date(timeIntervalSince1970: 1_709_251_200) // 2024-03-01

    private func item(_ title: String, created: Date = .now, updated: Date = .now,
                      lastUsed: Date? = nil, useCount: Int = 0) -> VaultItem {
        VaultItem(category: .login, title: title, lastUsedAt: lastUsed,
                  useCount: useCount, createdAt: created, updatedAt: updated)
    }

    func testDefaultMatchesLegacyUpdatedOrder() {
        let items = [item("A", updated: jan), item("B", updated: mar), item("C", updated: feb)]
        XCTAssertEqual(VaultSort().apply(items).map(\.title), ["B", "C", "A"],
                       "default is Date Modified, newest first")
        XCTAssertEqual(VaultSort.updated, VaultSort(),
                       "the pre-redesign .updated default is the struct default")
    }

    func testTitleSortBothDirections() {
        let items = [item("banana"), item("Apple"), item("cherry")]
        XCTAssertEqual(VaultSort(key: .title).apply(items).map(\.title),
                       ["Apple", "banana", "cherry"])
        XCTAssertEqual(VaultSort(key: .title, reversed: true).apply(items).map(\.title),
                       ["cherry", "banana", "Apple"])
    }

    func testDateAndUsageSorts() {
        let a = item("A", created: feb, lastUsed: jan, useCount: 1)
        let b = item("B", created: jan, lastUsed: mar, useCount: 5)
        let c = item("C", created: mar, lastUsed: nil, useCount: 0)
        XCTAssertEqual(VaultSort(key: .created).apply([a, b, c]).map(\.title), ["C", "A", "B"])
        XCTAssertEqual(VaultSort(key: .created, reversed: true).apply([a, b, c]).map(\.title),
                       ["B", "A", "C"])
        XCTAssertEqual(VaultSort(key: .recentlyUsed).apply([a, b, c]).map(\.title), ["B", "A", "C"],
                       "never-used items sink to the end")
        XCTAssertEqual(VaultSort(key: .frequentlyUsed).apply([a, b, c]).map(\.title), ["B", "A", "C"],
                       "most used first")
    }

    func testMonthSectionsGroupByMonthOfActiveKey() {
        let a = item("A", updated: mar.addingTimeInterval(86_400))
        let b = item("B", updated: mar)
        let c = item("C", updated: jan)
        let sort = VaultSort(key: .modified)
        let sections = sort.monthSections(sort.apply([c, b, a]))
        XCTAssertEqual(sections?.count, 2)
        XCTAssertEqual(sections?.first?.items.map(\.title), ["A", "B"])
        XCTAssertEqual(sections?.last?.items.map(\.title), ["C"])
    }

    func testNonDateKeysRenderFlat() {
        let items = [item("A")]
        XCTAssertNil(VaultSort(key: .title).monthSections(items))
        XCTAssertNil(VaultSort(key: .frequentlyUsed).monthSections(items))
        XCTAssertNil(VaultSort(key: .recentlyUsed).monthSections(items),
                     "Recently Used has no bucket for never-used items, so it stays flat")
    }

    func testSeedSpaceNameRecognisesEveryEra() {
        XCTAssertTrue(SeedSpaceName.isSeedName("My Vault"))
        XCTAssertTrue(SeedSpaceName.isSeedName("Kho của tôi"))
        XCTAssertTrue(SeedSpaceName.isSeedName("マイ保管庫"))
        XCTAssertTrue(SeedSpaceName.isSeedName("Nhóm của tôi"))
        XCTAssertFalse(SeedSpaceName.isSeedName("Work"))
    }

    func testFrequentlyUsedIgnoresStaleReversedFlag() {
        let items = [item("A", useCount: 1), item("B", useCount: 5)]
        // `reversed` survives key switches by design; a key without a direction
        // picker must ignore it rather than silently invert its ranking.
        XCTAssertEqual(VaultSort(key: .frequentlyUsed, reversed: true).apply(items).map(\.title),
                       ["B", "A"], "most used stays first even with a stale reversed flag")
    }

    func testSeedNameCatalogValuesStayInHistoricalSet() {
        // The localized values of the seed-name keys are STORAGE constants: a
        // reworded translation would eject freshly-seeded vaults from
        // `SeedSpaceName.historical` and break seed dedupe forever.
        for code in ["en", "vi", "ja"] {
            for key in ["My Space", "My Vault"] {
                var resource = LocalizedStringResource(String.LocalizationValue(key))
                resource.locale = Locale(identifier: code)
                let resolved = String(localized: resource)
                XCTAssertTrue(SeedSpaceName.historical.contains(resolved),
                              "catalog value for \(key) [\(code)] = \(resolved) must stay in SeedSpaceName.historical")
            }
        }
    }
}
