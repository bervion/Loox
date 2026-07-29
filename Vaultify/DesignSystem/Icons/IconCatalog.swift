import Foundation

/// One pickable icon: the SF Symbol plus the English terms that should find it.
struct CatalogIcon: Identifiable, Hashable {
    /// SF Symbol name, guaranteed present on the iOS 17.3 deployment floor.
    let symbol: String
    /// Lowercase English search terms, space separated. Matched alongside the symbol name so
    /// "car" finds `car.fill` and "wifi" finds `network`.
    let keywords: String

    /// The form written to the vault when this icon is picked.
    var token: String { IconResolver.token(symbol) }
    var id: String { symbol }
}

/// A browsable group in the icon picker.
struct IconCatalogSection: Identifiable {
    let key: String
    let title: LocalizedStringResource
    let icons: [CatalogIcon]
    var id: String { key }
}

/// The icon library offered by the Space and item pickers.
///
/// Every symbol here is checked against the iOS 17.3 SF Symbols set by `IconCatalogTests`.
/// A symbol added in a later release compiles without a warning and renders as an empty box on
/// a 17.3 device, so the test is the only thing standing between a typo and a blank icon in a
/// shipped build.
enum IconCatalog {
    static let sections: [IconCatalogSection] = IconCatalogData.sections

    /// Flat list, used by the tests and by search.
    static var allIcons: [CatalogIcon] { sections.flatMap(\.icons) }

    /// Stored token for a brand-new Space. The first icon of the first section by construction,
    /// so the picker's default and the model's default can never drift apart.
    static var defaultToken: String {
        sections.first?.icons.first.map(\.token) ?? IconResolver.token("folder.fill")
    }

    /// Icons matching a free-text query, searched over both the symbol name and its keywords.
    /// Dots and spaces are equivalent so "credit card" finds `creditcard.fill`.
    static func search(_ query: String) -> [CatalogIcon] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return [] }
        return allIcons.filter { icon in
            normalize(icon.symbol).contains(needle) || icon.keywords.contains(needle)
        }
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
