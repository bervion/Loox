import Foundation

/// One pickable icon: the stored glyph name plus the English terms that should find it.
struct CatalogIcon: Identifiable, Hashable {
    /// The value STORED when this icon is picked, and the value handed to `VaultIcon`: a bundled
    /// duotone asset name, or an `sf:`-prefixed SF Symbol. It must stay stable — a rename orphans
    /// every vault that already holds it.
    let name: String

    /// True for the SF additions, false for the app's own duotone glyphs.
    var isSystemSymbol: Bool { name.hasPrefix(IconResolver.systemPrefix) }
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

/// The icon library offered by the Space and item pickers: the app's duotone set, plus SF
/// Symbols as additional choices.
///
/// Both families fail the same silent way — a missing asset and an SF symbol newer than the
/// deployment floor each render an empty tile with no crash and no log — so `IconCatalogTests`
/// checks every entry of both.
enum IconCatalog {
    static let sections: [IconCatalogSection] = IconCatalogData.sections

    /// Flat list, used by the tests and by search.
    static var allIcons: [CatalogIcon] { sections.flatMap(\.icons) }

    /// The icon the very first Space is seeded with.
    ///
    /// A literal, deliberately NOT `Icons.lockFill`: that chrome token must stay free to restyle
    /// independently of stored data. The value must also stay byte-identical across versions —
    /// the seeded-Space dedupe signature compares it across devices, so changing it would leave
    /// two seeded Spaces that never converge. It renders as the modern duotone glyph through
    /// `IconResolver.legacySpaceAlias`; the stored bytes never change.
    static let seedSpaceIcon = "ic_lock_filled"

    /// Stored value for a brand-new Space. The first icon of the first section by construction,
    /// so the picker's default and the model's default can never drift apart.
    static var defaultToken: String {
        sections.first?.icons.first.map(\.name) ?? "dt_folder"
    }

    /// Icons matching a free-text query, searched over both the name and its keywords. The
    /// `dt_`/`sf:` prefixes, underscores and dots are stripped, so "credit card" finds both
    /// `dt_credit_card` and `sf:creditcard.fill`.
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
        if value.hasPrefix(IconResolver.systemPrefix) { value.removeFirst(IconResolver.systemPrefix.count) }
        return value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
