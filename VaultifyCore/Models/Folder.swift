import Foundation

/// A folder ("Space") decoded in memory while the vault is unlocked. Groups
/// items by context (company, project, personal…). An item references at most
/// one folder via `VaultItem.folderId`; `nil` means Unfiled.
///
/// The name is user data and is sealed at rest (see `FolderSecret`). The icon,
/// color, and sort order are non-secret presentation metadata kept plaintext on
/// `FolderRecord` so the Spaces grid can render without unsealing every folder.
nonisolated struct Folder: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var iconAsset: String
    var color: FolderColor
    var sortIndex: Int
    var createdAt: Date
    var updatedAt: Date
    /// Sealed link to the persona that owns this Space. nil = unassigned. Not
    /// auto-populated today (the persona's `primarySpaceID` is the authoritative
    /// link); a writer sets it via `updateFolder` so `updatedAt` bumps (LWW).
    var personaId: String?

    init(id: String = UUID().uuidString,
         name: String,
         iconAsset: String = "ic_folder",
         color: FolderColor = .blue,
         sortIndex: Int = 0,
         createdAt: Date = .now,
         updatedAt: Date = .now,
         personaId: String? = nil) {
        self.id = id
        self.name = name
        self.iconAsset = iconAsset
        self.color = color
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.personaId = personaId
    }

    /// The portion sealed (AES-256-GCM) at rest.
    var secret: FolderSecret { FolderSecret(name: name, personaId: personaId) }
}

/// The encrypted-at-rest payload of a folder. Only the name is secret.
nonisolated struct FolderSecret: Codable, Sendable {
    var name: String
    /// Sealed link from this Space to the identity that owns it. Nil today —
    /// nothing writes it yet; the field exists so the linkage can be added later
    /// without re-sealing every existing folder. Optional means old sealed blobs
    /// (which lack the key) decode cleanly to nil. Any future writer MUST re-seal
    /// through `updateFolder` so `updatedAt` bumps, otherwise the whole-record
    /// last-writer-wins pull gate silently drops the change.
    var personaId: String?
}
