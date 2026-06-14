import SwiftUI

/// Push destinations within the Vault tab's `NavigationStack`. Item detail is
/// keyed separately by the item id (`String`).
enum VaultRoute: Hashable {
    case all
    case folder(String?)   // nil = Unfiled
    case tag(String)
    case manageFolders
}

/// Sort order shared by the item browse lists.
enum VaultSort: String, CaseIterable, Identifiable {
    case updated, title
    var id: String { rawValue }
    var label: LocalizedStringKey { self == .updated ? "Recently Updated" : "Title" }

    func apply(_ items: [VaultItem]) -> [VaultItem] {
        switch self {
        case .updated: items.sorted { $0.updatedAt > $1.updatedAt }
        case .title: items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}
