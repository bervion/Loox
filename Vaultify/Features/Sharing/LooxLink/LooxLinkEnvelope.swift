import Foundation

/// Plaintext payload of a Loox Link (schema `loox-link-envelope-v1`).
/// Built on device and AES-256-GCM-encrypted BEFORE upload — this JSON never
/// leaves the device in the clear. Excluded fields must be ABSENT from the
/// array entirely: a hidden-but-present field is a leak, not a hint.
nonisolated struct LooxLinkEnvelope: Codable, Equatable, Sendable {
    nonisolated struct Field: Codable, Equatable, Sendable {
        var label: String
        var value: String
        /// Display hint only — the viewer masks the value behind a Reveal
        /// button. NOT a security boundary (the value is already decrypted
        /// client-side by then).
        var concealed: Bool?
        /// Semantic hint (`username|password|url|note|otp-code|custom`) for
        /// viewer icons/formatting. Reserved; the viewer may ignore it.
        var kind: String?
    }

    /// Must equal the request's `crypto_version`.
    var version: Int = 1
    /// Ordered — the viewer preserves this order.
    var fields: [Field]

    func encoded() throws -> Data { try JSONEncoder().encode(self) }
}

extension LooxLinkEnvelope {
    /// Item fields that may be offered for a quick link, in item order.
    /// Hard-excluded (never offered, regardless of selection): TOTP fields
    /// (the seed must never leave the vault — a snapshot of it would be a
    /// permanent secret hand-over), extra-protected (`guard2`) values (sealed
    /// under a separate code the unlocked vault can't read), attachments,
    /// key material (protected multiline — SSH private keys, recovery codes:
    /// a one-shot link has no recipient identity and no revocation of the
    /// copy, so key material is absolutely denied here), and empty values.
    static func shareableFields(of item: VaultItem) -> [DynamicField] {
        item.fields.filter { TransitionalSharePolicy.quickShareAllows($0) }
    }

    /// Default selection: the credential trio (username/email, website,
    /// password). Notes and custom fields start off — the owner opts in.
    static func defaultSelectedFieldIDs(of item: VaultItem) -> Set<String> {
        Set(shareableFields(of: item).filter { field in
            switch field.kind {
            case .username, .email, .url, .password: true
            default: false
            }
        }.map(\.id))
    }

    /// Build the envelope from the owner's selection. Only selected AND
    /// shareable fields appear; labels are localized to the owner's in-app
    /// language so the recipient sees "Mật khẩu"/"Password" as the owner does.
    static func build(item: VaultItem, selectedFieldIDs: Set<String>) -> LooxLinkEnvelope {
        let fields = shareableFields(of: item)
            .filter { selectedFieldIDs.contains($0.id) }
            .map { field in
                Field(label: appLabel(field.label),
                      value: field.value,
                      concealed: field.protected ? true : nil,
                      kind: viewerKind(for: field.kind))
            }
        return LooxLinkEnvelope(fields: fields)
    }

    private static func viewerKind(for kind: FieldKind) -> String {
        switch kind {
        case .username, .email: "username"
        case .password: "password"
        case .url: "url"
        case .text, .multiline: "note"
        default: "custom"
        }
    }
}
