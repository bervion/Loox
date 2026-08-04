import Foundation

/// What an icon name actually renders as, once the legacy Polaris namespace is folded in.
nonisolated enum IconGlyph: Equatable {
    /// An SF Symbol, drawn with the system's optical sizing.
    case system(String)
    /// A bundled template asset — a legacy glyph with no SF equivalent.
    case asset(String)
}

/// Translates every icon name the app can encounter into the glyph that renders.
///
/// Names arrive from three places and only the first is ours to change freely:
/// - `Icons` chrome tokens, compiled into the app as `sf:` values;
/// - values PERSISTED in a vault (a Space's `iconAsset`, an item's custom avatar), which may
///   be anything a past build ever wrote — `dt_folder`, `ic_lock_filled`, or a current `sf:` value;
/// - values pulled from CloudKit, written by a device on a different app version.
///
/// Stored values are deliberately never rewritten. `FolderRecord.iconAsset` is a plaintext
/// column pushed verbatim to CloudKit and merged last-writer-wins, so a bulk rename would blank
/// icons on every device still running an older build, and item avatars live inside the sealed
/// blob where a rewrite means unseal → re-seal → re-dirty the entire vault. Translating here
/// instead costs nothing at rest: an old build keeps rendering its original asset.
nonisolated enum IconResolver {
    /// Marks a stored value as an SF Symbol name. A prefix inside the existing `String` column
    /// keeps the two namespaces unambiguous without a schema change — there is no
    /// `VersionedSchema` in this project, so an added column would be its own migration.
    static let systemPrefix = "sf:"

    /// The stored form of an SF Symbol name.
    static func token(_ systemName: String) -> String { systemPrefix + systemName }

    static func resolve(_ name: String) -> IconGlyph {
        if name.hasPrefix(systemPrefix) {
            return .system(String(name.dropFirst(systemPrefix.count)))
        }
        return .asset(name)
    }

    /// Canonical form for comparing two icon names that may be written in different namespaces.
    ///
    /// The seeded-Space dedupe signature compares stored icon strings across devices to decide
    /// whether two seeded Spaces are the same Space, so both sides must be normalised before
    /// comparison rather than compared raw. Legacy Space glyph spellings fold here too, so a
    /// store that predates the duotone restyle still matches one whose user re-picked the
    /// modern glyph.
    static func canonical(_ name: String) -> String {
        switch resolve(legacySpaceAlias(name)) {
        case .system(let symbol): return systemPrefix + symbol
        case .asset(let asset): return asset
        }
    }

    /// Legacy Space glyphs folded to their modern duotone picker equivalents, for display and
    /// comparison only. Applied in `canonical()` (dedupe + picker selection) and the folder
    /// render paths (`FolderBadge`, `Folder.displayIcon`) — deliberately NOT in `resolve()`,
    /// because the raw names double as app-chrome tokens (`Icons.lockFill`, `Icons.folder`)
    /// whose rendering must not change.
    static func legacySpaceAlias(_ name: String) -> String {
        switch name {
        case "ic_lock_filled": "dt_lock"
        case "ic_folder": "dt_folder"
        default: name
        }
    }
}
