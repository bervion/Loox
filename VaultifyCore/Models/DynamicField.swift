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

    init(id: String = UUID().uuidString,
         label: String,
         kind: FieldKind,
         value: String = "",
         protected: Bool? = nil,
         guard2: Bool? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.value = value
        self.protected = protected ?? kind.defaultsProtected
        self.guard2 = guard2
    }

    var isExtraProtected: Bool { guard2 == true }
    var isEmpty: Bool { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
