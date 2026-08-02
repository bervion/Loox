import Foundation

/// Field-level effective policy — what one field may do on outbound surfaces.
/// Derived, never stored: items do not persist their own authority.
nonisolated struct FieldCapabilities: Equatable, Sendable {
    /// May appear in a Quick Link / Quick View snapshot share.
    var quickShare = false
    /// May be OFFERED for per-item Approval sharing.
    var approvalShare = false
    /// May feed the decrypted-memory search index.
    var searchIndex = false
    /// May leave the vault in a plaintext export surface (CSV columns).
    var plaintextExport = false
    /// What the user must do before reveal/copy/export of the VALUE.
    var revealAuthorization: ActionAuthorization = .none
    /// Effective sensitivity (registry minimum tightened by stored policy).
    var sensitivity: Sensitivity = .secret

    /// Fail-closed default: visible, masked, nothing leaves.
    static let none = FieldCapabilities()
}

/// The ONLY authority integrations may ask about what an item or field is
/// allowed to do. Pure and deterministic; unknown identity means fail closed.
///
/// Layering:
/// - Item with a registry-known `kindID` → that template's capability matrix.
/// - Legacy item (no `kindID`, known category) → the legacy template mapped
///   from its category — parity with shipped behavior for all eight.
/// - Unknown `kindID`, unknown category, or unsupported schema → zero
///   external capability (visible and recoverable, nothing else).
nonisolated enum ItemCapabilityResolver {

    // MARK: Item level

    static func capabilities(for item: VaultItem) -> ItemCapabilities {
        // Anything from a newer incompatible generation: recovery only.
        guard !item.isUnsupportedSchema else { return .none }
        // Unknown category raw (newer writer): never infer behavior from the
        // `.custom` presentation fallback.
        guard item.unknownCategoryRaw == nil else { return .none }
        if let kindID = item.semantics?.kindID {
            guard let template = ItemTemplateRegistry.definition(for: kindID) else {
                return .none // future kind — visible, zero capability
            }
            return template.capabilities
        }
        // Legacy item: category-mapped template (the eight are all registered).
        return ItemTemplateRegistry.definition(forLegacy: item.category)?.capabilities ?? .none
    }

    /// Login-style AutoFill/QuickType eligibility — capability AND the
    /// concrete usable material (parity with the shipped duck-typing, now
    /// bounded by template policy).
    static func isFillableLogin(_ item: VaultItem) -> Bool {
        capabilities(for: item).loginAutoFill && item.passwordField != nil
    }

    /// May this item's usable TOTP feed authenticator surfaces?
    static func isTOTPSource(_ item: VaultItem) -> Bool {
        capabilities(for: item).totpSource && item.totpField != nil
    }

    // MARK: Field level

    static func capabilities(for field: DynamicField, in item: VaultItem) -> FieldCapabilities {
        let itemCaps = capabilities(for: item)
        // Effective policy = registry minimum (by role, within the item's
        // template) tightened by stored semantics. Roles the registry does
        // not know — or a known role on the WRONG template — get secret-safe
        // defaults and zero outbound capability.
        let registryDescriptor = registryDescriptor(for: field, in: item)
        let hasUnknownRole = field.roleID != nil && registryDescriptor == nil

        var sensitivity = registryDescriptor?.sensitivity
            ?? fallbackSensitivity(for: field, unknownRole: hasUnknownRole)
        if let stored = field.semantics?.sensitivity {
            sensitivity = Sensitivity.stricter(sensitivity, stored)
        }
        var authorization = registryDescriptor?.actionAuthorization ?? .none
        if hasUnknownRole { authorization = .reauthenticate }
        if let stored = field.semantics?.actionAuthorization {
            authorization = ActionAuthorization.stricter(authorization, stored)
        }
        if field.isExtraProtected {
            authorization = ActionAuthorization.stricter(authorization, .level2)
        }

        var caps = FieldCapabilities()
        caps.sensitivity = sensitivity
        caps.revealAuthorization = authorization

        // Outbound surfaces: the item must be eligible AND the field must be
        // individually admissible. Key material never leaves through a share
        // or plaintext export; unknown roles never leave at all.
        let valueLeavable = !field.isExtraProtected && !hasUnknownRole
            && field.unknownKindRaw == nil && sensitivity < .keyMaterial

        caps.quickShare = itemCaps.quickShareEligible && valueLeavable
            && quickShareKindAllows(field)
        caps.approvalShare = itemCaps.approvalShareEligible && valueLeavable
            && approvalShareKindAllows(field)
        caps.plaintextExport = valueLeavable && sensitivity < .secret
        caps.searchIndex = !field.protected && !field.isExtraProtected
            && !hasUnknownRole && sensitivity <= .private
        return caps
    }

    /// The registry-minimum descriptor for this field's role WITHIN the item's
    /// own template. A role from a different template does not transfer its
    /// policy (wrong-template roles are treated as unknown).
    private static func registryDescriptor(
        for field: DynamicField, in item: VaultItem
    ) -> TemplateFieldDescriptor? {
        guard let roleID = field.roleID else { return nil }
        let template: ItemTemplateDefinition?
        if let kindID = item.semantics?.kindID {
            template = ItemTemplateRegistry.definition(for: kindID)
        } else {
            template = ItemTemplateRegistry.definition(forLegacy: item.category)
        }
        return template?.descriptor(for: roleID)
    }

    /// Sensitivity when no role policy applies: derived from display masking
    /// (the shipped behavior), except unknown roles which are secret-safe.
    private static func fallbackSensitivity(for field: DynamicField,
                                            unknownRole: Bool) -> Sensitivity {
        if unknownRole { return .secret }
        if field.isExtraProtected { return .secret }
        if field.protected {
            // Key material recognition without semantics: protected multiline
            // is how SSH private keys and recovery codes ship today.
            return field.kind.isMultiline ? .keyMaterial : .secret
        }
        return .private
    }

    /// Kind-shape rules shared with the transitional policy: snapshot shares.
    private static func quickShareKindAllows(_ field: DynamicField) -> Bool {
        guard !field.isEmpty else { return false }
        switch field.kind {
        case .totp, .fileRef: return false
        case .multiline: return !field.protected
        default: return true
        }
    }

    private static func approvalShareKindAllows(_ field: DynamicField) -> Bool {
        switch field.kind {
        case .fileRef: return false
        case .multiline: return !field.protected
        default: return true
        }
    }
}
