import Foundation

/// Minimal, immutable projection of one vault item for audit rules.
/// Holds the plaintext password only for the lifetime of the audit task —
/// snapshots are never persisted (only finding metadata is).
nonisolated struct VaultAuditItem: Identifiable, Sendable {
    let id: String
    let category: ItemCategory
    let title: String
    let usernames: [String]
    let password: String?
    let totpSecret: String?
    let hasTOTP: Bool
    let hasPasskey: Bool
    /// Raw values of every website field (items support multiple websites).
    let rawURLs: [String]
    let createdAt: Date
    let updatedAt: Date
    let lastUsedAt: Date?
    /// Rotation cadence in days (0 = off) and explicit change baseline.
    let rotateDays: Int
    let passwordChangedAt: Date?
    let isTrashed: Bool

    var hasPassword: Bool { !(password ?? "").isEmpty }
}

/// The full input to one audit run.
nonisolated struct VaultAuditSnapshot: Sendable {
    let items: [VaultAuditItem]
    let personaID: String?
    let capturedAt: Date

    /// Items rules should normally analyze (trash excluded).
    var activeItems: [VaultAuditItem] { items.filter { !$0.isTrashed } }

    /// Builds a snapshot from decrypted items. `passkeyItemIDs` is injected by the
    /// caller (passkey↔item linkage lives in the app's repository, not in core).
    static func make(items: [VaultItem],
                     personaID: String? = nil,
                     passkeyItemIDs: Set<String> = [],
                     now: Date = .now) -> VaultAuditSnapshot {
        let auditItems = items.map { item in
            // Extra-protected values are sealed ciphertext here: scoring one as
            // a password would grade random-looking noise as "strong" and hide
            // reuse across items. Sealed fields drop out of quality analysis;
            // presence checks (2FA) keep counting the field's existence.
            let password = item.passwordField.flatMap { $0.isExtraProtected ? nil : $0.value }
            return VaultAuditItem(
                id: item.id,
                category: item.category,
                title: item.title,
                usernames: item.fields
                    .filter { ($0.kind == .username || $0.kind == .email)
                        && !$0.isEmpty && !$0.isExtraProtected }
                    .map(\.value),
                password: password,
                totpSecret: item.totpField?.value,
                hasTOTP: item.fields.contains { $0.kind == .totp && !$0.isEmpty },
                hasPasskey: passkeyItemIDs.contains(item.id),
                rawURLs: item.fields.filter { $0.kind == .url && !$0.isEmpty }.map(\.value),
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                lastUsedAt: item.lastUsedAt,
                rotateDays: item.rotateDays,
                passwordChangedAt: item.passwordChangedAt,
                isTrashed: item.isTrashed)
        }
        return VaultAuditSnapshot(items: auditItems, personaID: personaID, capturedAt: now)
    }
}
