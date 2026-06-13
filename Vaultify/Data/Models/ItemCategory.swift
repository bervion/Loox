import Foundation

/// Top-level classification of a vault item. Mirrors the reference app's
/// taxonomy. Stored inside the sealed payload, never in plaintext at rest.
nonisolated enum ItemCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case login
    case note
    case card
    case identity
    case sshKey
    case custom

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .login: return "Login"
        case .note: return "Secure Note"
        case .card: return "Payment Card"
        case .identity: return "Identity"
        case .sshKey: return "SSH Key"
        case .custom: return "Custom"
        }
    }

    /// Polaris icon asset backing this category.
    var iconAsset: String {
        switch self {
        case .login: return "ic_globe"
        case .note: return "ic_note"
        case .card: return "ic_credit_card"
        case .identity: return "ic_identity_card"
        case .sshKey: return "ic_key"
        case .custom: return "ic_metafields"
        }
    }

    /// Default fields used when creating a new item of this category. Labels are
    /// English source strings; the UI localizes them via the string catalog and
    /// passes user-authored labels through verbatim.
    var fieldTemplate: [DynamicField] {
        switch self {
        case .login:
            return [
                DynamicField(label: "Username", kind: .username),
                DynamicField(label: "Password", kind: .password, protected: true),
                DynamicField(label: "Website", kind: .url),
                DynamicField(label: "One-time Code", kind: .totp, protected: true),
            ]
        case .note:
            return [DynamicField(label: "Note", kind: .multiline)]
        case .card:
            return [
                DynamicField(label: "Cardholder", kind: .text),
                DynamicField(label: "Card Number", kind: .monospace, protected: true),
                DynamicField(label: "Expiry", kind: .text),
                DynamicField(label: "Security Code", kind: .monospace, protected: true),
            ]
        case .identity:
            return [
                DynamicField(label: "Full Name", kind: .text),
                DynamicField(label: "ID Number", kind: .monospace, protected: true),
                DynamicField(label: "Date of Birth", kind: .date),
            ]
        case .sshKey:
            return [
                DynamicField(label: "Private Key", kind: .multiline, protected: true),
                DynamicField(label: "Public Key", kind: .multiline),
            ]
        case .custom:
            return [DynamicField(label: "Field", kind: .text)]
        }
    }
}
