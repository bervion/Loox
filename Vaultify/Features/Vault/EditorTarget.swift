import Foundation

/// What the item editor sheet should edit: a new item of a category, or an
/// existing item.
enum EditorTarget: Identifiable {
    case new(ItemCategory)
    case edit(VaultItem)
    /// A brand-new item pre-filled from outside (e.g. an imported `otpauth://` 2FA setup).
    /// Saved as a new item like `.new`, but starts from the provided draft.
    case draft(VaultItem)
    /// Explicit private-address context survives sealed draft restoration.
    case aliasLogin(VaultItem, aliasID: String, personaID: String, relationRevision: UInt64)
    case restored(UIStateStore.DraftState)

    var id: String {
        switch self {
        case .new(let category): return "new-\(category.rawValue)"
        case .edit(let item): return "edit-\(item.id)"
        case .draft(let item): return "draft-\(item.id)"
        case .aliasLogin(let item, _, _, _): return "alias-login-\(item.id)"
        case .restored(let draft): return "restored-\(draft.id)"
        }
    }

    /// A brand-new item created from a registry template: fields carry their
    /// semantic roles and the item its stable kind ID from the first byte.
    static func newFromTemplate(_ template: ItemTemplateDefinition) -> EditorTarget {
        var item = VaultItem(category: template.legacyCategory, title: "",
                             fields: template.defaultFields)
        item.semantics = template.newItemSemantics
        return .draft(item)
    }
}
