import Foundation

/// What the item editor sheet should edit: a new item of a category, or an
/// existing item.
enum EditorTarget: Identifiable {
    case new(ItemCategory)
    case edit(VaultItem)
    /// A brand-new item pre-filled from outside (e.g. an imported `otpauth://` 2FA setup).
    /// Saved as a new item like `.new`, but starts from the provided draft.
    case draft(VaultItem)

    var id: String {
        switch self {
        case .new(let category): return "new-\(category.rawValue)"
        case .edit(let item): return "edit-\(item.id)"
        case .draft(let item): return "draft-\(item.id)"
        }
    }
}
