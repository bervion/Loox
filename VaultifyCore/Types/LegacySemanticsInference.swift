import Foundation

/// Conservative, PURE inference of semantic identity for legacy (pre-semantic)
/// items. Only provable facts become authoritative:
///
/// - The item kind follows from `category` (definitional — category IS the
///   legacy identity).
/// - A field role is assigned only where category + kind + cardinality make it
///   unambiguous. Editable labels and field position may only ever SUGGEST a
///   user-confirmed conversion elsewhere; they never grant a role here.
///
/// Ambiguous fields stay role-less (safe: the resolver treats them by their
/// masking policy). Inference runs in memory on decode; roles persist only
/// when a user edit re-seals the item (lazy migration — never a bulk rewrite
/// that could partially fail).
nonisolated enum LegacySemanticsInference {

    /// Returns the item with inferred semantics attached, or unchanged when
    /// inference does not apply (already semantic, unknown category, or
    /// unsupported schema).
    static func applied(to item: VaultItem) -> VaultItem {
        guard item.semantics?.kindID == nil,
              item.unknownCategoryRaw == nil,
              !item.isUnsupportedSchema,
              item.sharedOrigin == nil else { return item }

        var updated = item
        var semantics = item.semantics ?? ItemSemantics()
        semantics.kindID = ItemTemplateRegistry.legacyKind(for: item.category)
        updated.semantics = semantics

        updated.fields = item.fields.map { field in
            guard field.semantics?.roleID == nil,
                  let role = provableRole(for: field, in: item) else { return field }
            var f = field
            var fs = f.semantics ?? FieldSemantics()
            fs.roleID = role
            f.semantics = fs
            return f
        }
        return updated
    }

    /// The role a field PROVABLY carries, or nil.
    private static func provableRole(for field: DynamicField,
                                     in item: VaultItem) -> FieldRoleID? {
        guard field.unknownKindRaw == nil else { return nil }
        switch item.category {
        case .login:
            // Kind is authoritative within a login: that is exactly how every
            // shipped integration already treats these fields.
            switch field.kind {
            case .password: return .password
            case .username, .email: return .username
            case .totp: return .totp
            case .url: return .website
            default: return nil
            }
        case .note:
            // The single body field of a note.
            let multilines = item.fields.filter { $0.kind.isMultiline }
            return field.kind.isMultiline && multilines.count == 1 ? .noteBody : nil
        case .sshKey:
            // Template shape: exactly one protected multiline (private key)
            // and at most one plain multiline (public key). Any other shape is
            // user-modified and stays role-less.
            let protectedMultiline = item.fields.filter { $0.kind.isMultiline && $0.protected }
            let plainMultiline = item.fields.filter { $0.kind.isMultiline && !$0.protected }
            if field.kind.isMultiline, field.protected, protectedMultiline.count == 1 {
                return .sshPrivateKey
            }
            if field.kind.isMultiline, !field.protected, plainMultiline.count == 1 {
                return .sshPublicKey
            }
            return nil
        case .recoveryCodes:
            let protectedMultiline = item.fields.filter { $0.kind.isMultiline && $0.protected }
            return field.kind.isMultiline && field.protected && protectedMultiline.count == 1
                ? .recoveryCodes : nil
        case .card, .identity, .securityQuestions, .custom:
            // Label-dependent shapes: labels are editable and localized, so
            // nothing here is provable. (Label matches may power a
            // user-confirmed conversion flow, never silent authority.)
            return nil
        }
    }
}
