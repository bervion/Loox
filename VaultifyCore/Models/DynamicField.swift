import Foundation

/// A single labelled value on a vault item.
///
/// `value` is always plaintext in memory; the repository encrypts the values of
/// `protected` fields inside the sealed item payload before persistence.
nonisolated struct DynamicField: Identifiable, Codable, Equatable, Sendable {
    var id: String
    /// Either a `field.*` localization key (template fields) or a user label.
    var label: String
    var kind: FieldKind
    /// Plaintext normally; when `guard2 == true` this holds the opaque
    /// second-layer `SecretGuard` payload (ciphertext) instead.
    var value: String
    var protected: Bool
    /// Extra ("Level-2") protection: the value is sealed under a separate code
    /// and cannot be read from the unlocked vault alone. Optional so items stored
    /// before this feature still decode.
    var guard2: Bool?
    /// Optional semantic identity/policy (role, sensitivity, authorization,
    /// lifecycle). Absent on legacy fields; written by template creation and
    /// lazy migration. Behavior keys off this, never off `label`.
    var semantics: FieldSemantics?
    /// The original `kind` raw value when it names a kind this build does not
    /// know (field written by a NEWER app). Presentation degrades to `.text`;
    /// re-encoding writes this raw value back — an edit-save cycle through an
    /// older build must never permanently downgrade the field.
    var unknownKindRaw: String?

    init(id: String = UUID().uuidString,
         label: String,
         kind: FieldKind,
         value: String = "",
         protected: Bool? = nil,
         guard2: Bool? = nil,
         semantics: FieldSemantics? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.value = value
        self.protected = protected ?? kind.defaultsProtected
        self.guard2 = guard2
        self.semantics = semantics
        self.unknownKindRaw = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, kind, value, protected, guard2, semantics
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        let rawKind = try c.decode(String.self, forKey: .kind)
        if let known = FieldKind(rawValue: rawKind) {
            kind = known
            unknownKindRaw = nil
        } else {
            kind = .text
            unknownKindRaw = rawKind
        }
        value = try c.decode(String.self, forKey: .value)
        protected = try c.decode(Bool.self, forKey: .protected)
        guard2 = try c.decodeIfPresent(Bool.self, forKey: .guard2)
        semantics = try c.decodeIfPresent(FieldSemantics.self, forKey: .semantics)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encode(unknownKindRaw ?? kind.rawValue, forKey: .kind)
        try c.encode(value, forKey: .value)
        try c.encode(protected, forKey: .protected)
        try c.encodeIfPresent(guard2, forKey: .guard2)
        try c.encodeIfPresent(semantics, forKey: .semantics)
    }

    var isExtraProtected: Bool { guard2 == true }
    var isEmpty: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// The stable role identity, if any — the ONLY key behavior may hang off.
    var roleID: FieldRoleID? { semantics?.roleID }
}
