import Foundation

/// What the item editor sheet should edit: a new item of a category, or an
/// existing item.
enum EditorTarget: Identifiable {
    case new(ItemCategory)
    case edit(VaultItem)

    var id: String {
        switch self {
        case .new(let category): return "new-\(category.rawValue)"
        case .edit(let item): return "edit-\(item.id)"
        }
    }
}
