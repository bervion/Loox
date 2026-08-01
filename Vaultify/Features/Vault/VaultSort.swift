import SwiftUI

/// Sort order shared by the item browse lists: what to order by plus a flipped
/// direction. The default (Date Modified, newest first) matches the repository's
/// reload order, so an untouched list reads the same as before sorting existed.
struct VaultSort: Hashable {
    enum Key: String, CaseIterable, Identifiable {
        case title, created, modified, frequentlyUsed, recentlyUsed

        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .title: "Title"
            case .created: "Date Created"
            case .modified: "Date Modified"
            case .frequentlyUsed: "Frequently Used"
            case .recentlyUsed: "Recently Used"
            }
        }

        /// Frequently Used is a ranking; a "least used first" flip is noise.
        var supportsDirection: Bool { self != .frequentlyUsed }

        /// The date month-year sections group by. Keys without one render flat:
        /// title and frequency are not timelines, and Recently Used would strand
        /// never-used items (no `lastUsedAt`) in a meaningless bucket.
        var sectionDate: ((VaultItem) -> Date)? {
            switch self {
            case .created: { $0.createdAt }
            case .modified: { $0.updatedAt }
            default: nil
            }
        }
    }

    var key: Key = .modified
    /// `false` = the key's natural reading (newest first / A to Z / most used);
    /// `true` flips it. A separate flag rather than per-key cases so switching
    /// keys in the menu preserves the direction the user already chose.
    var reversed = false

    /// The pre-redesign default; HomeScreen's recent strip still sorts with it.
    static let updated = VaultSort(key: .modified)

    func apply(_ items: [VaultItem]) -> [VaultItem] {
        let sorted = items.sorted { compare($0, $1) == .orderedAscending }
        // A key without a direction picker ignores a stale flag carried over
        // from a directional key — otherwise switching Title (Z to A) into
        // Frequently Used would silently list least-used first with no
        // visible control to undo it.
        return (reversed && key.supportsDirection) ? sorted.reversed() : sorted
    }

    /// Natural reading order per key: the item that should appear first compares
    /// ascending. Never returns contradictory answers for equal elements (strict
    /// weak ordering), which a naive `!ordered` flip would violate.
    private func compare(_ a: VaultItem, _ b: VaultItem) -> ComparisonResult {
        switch key {
        case .title:
            return a.title.localizedCaseInsensitiveCompare(b.title)
        case .created:
            return newestFirst(a.createdAt, b.createdAt)
        case .modified:
            return newestFirst(a.updatedAt, b.updatedAt)
        case .recentlyUsed:
            return newestFirst(a.lastUsedAt ?? .distantPast, b.lastUsedAt ?? .distantPast)
        case .frequentlyUsed:
            if a.useCount != b.useCount {
                return a.useCount > b.useCount ? .orderedAscending : .orderedDescending
            }
            return newestFirst(a.lastUsedAt ?? .distantPast, b.lastUsedAt ?? .distantPast)
        }
    }

    private func newestFirst(_ a: Date, _ b: Date) -> ComparisonResult {
        if a == b { return .orderedSame }
        return a > b ? .orderedAscending : .orderedDescending
    }
}

/// One month-year slice of a sectioned browse list.
struct VaultItemMonthSection: Identifiable {
    let id: String
    let title: String
    let items: [VaultItem]
}

extension VaultSort {
    /// Month-year groups over `items` (already ordered by `apply`); nil = the
    /// active key has no timeline and the list renders flat. Headers follow the
    /// in-app language (`appResourceLocale`), not the device locale.
    func monthSections(_ items: [VaultItem]) -> [VaultItemMonthSection]? {
        guard let date = key.sectionDate, !items.isEmpty else { return nil }
        let formatter = Self.monthFormatter()
        let calendar = Calendar.current
        var sections: [VaultItemMonthSection] = []
        var bucketKey = ""
        var bucketStart = Date.distantPast
        var bucket: [VaultItem] = []
        func flush() {
            guard !bucket.isEmpty else { return }
            sections.append(.init(id: bucketKey, title: formatter.string(from: bucketStart), items: bucket))
            bucket = []
        }
        for item in items {
            let itemDate = date(item)
            let comps = calendar.dateComponents([.year, .month], from: itemDate)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if key != bucketKey {
                flush()
                bucketKey = key
                bucketStart = itemDate
            }
            bucket.append(item)
        }
        flush()
        return sections
    }

    /// Month-year formatter cached per in-app locale (language switches live).
    private static var cachedMonthFormatter: (localeID: String, formatter: DateFormatter)?
    private static func monthFormatter() -> DateFormatter {
        let locale = appResourceLocale
        if let cached = cachedMonthFormatter, cached.localeID == locale.identifier {
            return cached.formatter
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        cachedMonthFormatter = (locale.identifier, formatter)
        return formatter
    }
}
