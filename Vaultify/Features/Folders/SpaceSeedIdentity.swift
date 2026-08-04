import Foundation

/// The seeded first Space's name across every build and language that ever
/// shipped, frozen as storage constants. Stored folder names are never
/// rewritten, so any value onboarding ever wrote must stay recognisable here
/// forever: the dedupe pass uses the set to match an untouched seed Space no
/// matter which app version or in-app language seeded it, and display maps any
/// of them to the current localized name.
nonisolated enum SeedSpaceName {
    /// Every localized value first-run seeding ever stored. Append-only.
    static let historical: Set<String> = [
        // Builds seeding appString("My Vault").
        "My Vault", "Kho của tôi", "マイ保管庫",
        // Builds seeding appString("My Space") — the Space-context rename.
        "My Space", "Nhóm của tôi", "マイスペース",
    ]

    /// The name a fresh seed stores, resolved in the current in-app language.
    static var current: String { appString("My Space") }

    /// Whether a stored folder name is an untouched seed name from any era.
    nonisolated static func isSeedName(_ name: String) -> Bool {
        historical.contains(name) || name == appString("My Space")
    }
}

/// The seeded first Space's glyph across every era, compared canonically.
enum SeedSpaceIcon {
    /// Dedupe/grouping key: `canonical()` already folds the raw legacy spelling
    /// (`ic_lock_filled` → `dt_lock`); this adds the SF-era seed spelling
    /// (`sf:lock.fill`, written by the build that briefly seeded an SF glyph).
    /// The SF fold lives HERE, not in `IconResolver.legacySpaceAlias`:
    /// "sf:lock.fill" is an offerable picker glyph, so a user's deliberate SF
    /// pick must keep rendering (and picker-highlighting) as SF.
    static func dedupeKey(_ icon: String) -> String {
        let canonical = IconResolver.canonical(icon)
        return canonical == "sf:lock.fill" ? IconResolver.canonical(IconCatalog.seedSpaceIcon) : canonical
    }

    /// Whether a stored glyph is an untouched seed glyph from any era.
    static func isSeedGlyph(_ icon: String) -> Bool {
        dedupeKey(icon) == IconResolver.canonical(IconCatalog.seedSpaceIcon)
    }
}

extension Folder {
    /// Untouched first-run seed: any-era seed name + any-era seed glyph + seed
    /// blue — the same narrowing the dedupe pass uses, so display and dedupe
    /// never drift. A folder that merely echoes a seed NAME (a CSV import, or
    /// a user's own naming) keeps its stored name verbatim.
    var isUntouchedSeed: Bool {
        SeedSpaceName.isSeedName(name) && SeedSpaceIcon.isSeedGlyph(iconAsset) && color == .blue
    }

    /// UI name: an untouched seed Space follows the in-app language; anything
    /// the user typed renders verbatim. Render-layer ONLY — never feed this
    /// into FolderEditorSheet's text field or any save path: stored names are
    /// never rewritten (the seed dedupe signature and CloudKit merge rely on
    /// the frozen bytes).
    var displayName: String {
        isUntouchedSeed ? SeedSpaceName.current : name
    }

    /// UI icon: legacy seed glyphs render as their modern duotone equivalents
    /// (`IconResolver.legacySpaceAlias`); the stored `iconAsset` stays untouched.
    var displayIcon: String { IconResolver.legacySpaceAlias(iconAsset) }
}
