import Foundation

/// One pickable icon: the glyph's name plus the English terms that should find it.
struct CatalogIcon: Identifiable, Hashable {
    /// Asset name of a bundled duotone glyph. This is also the value STORED when the icon is
    /// picked, so it must stay stable — a rename orphans every vault that already holds it.
    let name: String
    /// Lowercase English search terms, space separated. Matched alongside the name so "web"
    /// finds `dt_globe` and "2fa" finds `dt_clock`.
    let keywords: String

    var id: String { name }
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
/// Every name here must resolve to a bundled asset — `IconCatalogTests` fails the build if one
/// does not, because a missing asset renders as an empty tile with no crash and no log.
enum IconCatalog {
    static let sections: [IconCatalogSection] = IconCatalogData.sections

    /// Flat list, used by the tests and by search.
    static var allIcons: [CatalogIcon] { sections.flatMap(\.icons) }

    /// The icon the very first Space is seeded with.
    ///
    /// A literal, deliberately NOT `Icons.lockFill`: that token is app chrome and is now an SF
    /// symbol, whereas a Space badge is a content glyph. It must also stay byte-identical across
    /// versions — the seeded-Space dedupe signature compares this value across devices, so
    /// changing it would leave two "My Vault" Spaces that never converge.
    static let seedSpaceIcon = "ic_lock_filled"

    /// Stored value for a brand-new Space. The first icon of the first section by construction,
    /// so the picker's default and the model's default can never drift apart.
    static var defaultToken: String {
        sections.first?.icons.first.map(\.name) ?? "dt_folder"
    }

    /// Icons matching a free-text query, searched over both the name and its keywords. The
    /// `dt_` prefix and underscores are stripped so "credit card" finds `dt_credit_card`.
    static func search(_ query: String) -> [CatalogIcon] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return [] }
        return allIcons.filter { icon in
            normalize(icon.name).contains(needle) || icon.keywords.contains(needle)
        }
    }

    private static func normalize(_ text: String) -> String {
        var value = text.lowercased()
        if value.hasPrefix("dt_") { value.removeFirst(3) }
        return value
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
