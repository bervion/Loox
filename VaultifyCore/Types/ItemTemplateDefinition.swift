import Foundation

/// Where a template appears in the New Item picker.
nonisolated enum TemplateFamily: String, Sendable, CaseIterable {
    case common
    case developer
    case personal
    case finance
    case files
}

/// One field a template creates, with its authoritative semantics. Labels are
/// stable English source strings (localized at display via `appLabel`); the
/// ROLE is the behavioral identity.
nonisolated struct TemplateFieldDescriptor: Sendable {
    let roleID: FieldRoleID?
    let label: String
    let kind: FieldKind
    let protected: Bool
    /// Registry-minimum sensitivity for this role — stored policy may only
    /// tighten it.
    let sensitivity: Sensitivity
    let actionAuthorization: ActionAuthorization
    /// Included in the item's default field set at creation. Non-default
    /// descriptors describe roles the editor can ADD (advanced section).
    let isDefault: Bool
    /// Validator identifier resolved by the editor (`TemplateValidators`).
    let validatorID: String?

    init(roleID: FieldRoleID?, label: String, kind: FieldKind,
         protected: Bool = false,
         sensitivity: Sensitivity = .private,
         actionAuthorization: ActionAuthorization = .none,
         isDefault: Bool = true,
         validatorID: String? = nil) {
        self.roleID = roleID
        self.label = label
        self.kind = kind
        self.protected = protected
        self.sensitivity = sensitivity
        self.actionAuthorization = actionAuthorization
        self.isDefault = isDefault
        self.validatorID = validatorID
    }

    /// The `DynamicField` this descriptor creates, with semantics stamped.
    func makeField(sectionID: String?) -> DynamicField {
        DynamicField(label: label, kind: kind, protected: protected,
                     semantics: FieldSemantics(roleID: roleID,
                                               sectionID: sectionID,
                                               sensitivity: sensitivity,
                                               actionAuthorization: actionAuthorization))
    }
}

/// A titled group of fields in the editor/detail composition.
nonisolated struct TemplateSection: Sendable {
    let id: String
    /// English source string for the section header ("" = untitled core section).
    let title: String
    /// Collapsed behind an "Advanced" disclosure by default.
    let isAdvanced: Bool
    let fields: [TemplateFieldDescriptor]

    init(id: String, title: String = "", isAdvanced: Bool = false,
         fields: [TemplateFieldDescriptor]) {
        self.id = id
        self.title = title
        self.isAdvanced = isAdvanced
        self.fields = fields
    }
}

/// Item-level external-capability matrix. Every flag defaults to FALSE —
/// a template must affirmatively claim a capability, and unknown templates
/// get the zero value (fail closed).
nonisolated struct ItemCapabilities: Equatable, Sendable {
    var loginAutoFill = false        // QuickType password identities + AutoFill listing
    var totpSource = false           // OTP identities + authenticator lists
    var safariLoginListing = false   // Safari extension host-scoped login listing
    var identityFill = false         // Safari identity fill payload
    var cardFill = false             // Safari card fill payload
    var passwordAudit = false        // strength/reuse/HIBP pool membership
    var loginHygieneAudit = false    // 2FA/passkey/URL-hygiene/completeness rules
    var spaceShareEligible = false   // Space (family) share fan-out
    var quickShareEligible = false   // Quick Link / Quick View snapshot shares
    var approvalShareEligible = false // per-item Approval sharing
    var csvCredentialExport = false  // plaintext CSV credential columns
    var credentialExchangeExport = false // FIDO credential exchange

    /// The fail-closed zero value used for every unknown kind.
    static let none = ItemCapabilities()
}

/// A compile-time item template: identity, presentation, composition, and
/// capability policy. Definitions are code — never downloaded, never
/// user-supplied.
nonisolated struct ItemTemplateDefinition: Sendable {
    let kindID: ItemKindID
    /// Append-only creation provenance stamped on new items.
    let version: Int
    let family: TemplateFamily
    /// Coarse presentation + storage fallback so pre-semantic builds render
    /// the item sensibly.
    let legacyCategory: ItemCategory
    /// English source strings; UI localizes via the string catalog.
    let title: String
    let blurb: String
    /// Polaris single-tone chip icon + duotone avatar.
    let iconAsset: String
    let avatarIcon: String
    let sections: [TemplateSection]
    let capabilities: ItemCapabilities
    /// Role whose value makes the best list-row subtitle (resolver falls back
    /// to username/url heuristics when absent).
    let subtitleRole: FieldRoleID?

    /// Default fields for a new item, semantics stamped.
    var defaultFields: [DynamicField] {
        sections.flatMap { section in
            section.fields.filter(\.isDefault).map { $0.makeField(sectionID: section.id) }
        }
    }

    /// Fresh item-level semantics for a newly created item of this template.
    var newItemSemantics: ItemSemantics {
        ItemSemantics(kindID: kindID, templateVersion: version)
    }

    /// The registry-minimum policy for a role in THIS template, if the role
    /// belongs to it.
    func descriptor(for roleID: FieldRoleID) -> TemplateFieldDescriptor? {
        for section in sections {
            if let d = section.fields.first(where: { $0.roleID == roleID }) { return d }
        }
        return nil
    }
}
