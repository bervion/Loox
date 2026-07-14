import Foundation

/// Top-level classification of a vault item. Mirrors the reference app's
/// taxonomy. Stored inside the sealed payload, never in plaintext at rest.
nonisolated enum ItemCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case login
    case note
    case card
    case identity
    case sshKey
    case recoveryCodes
    case securityQuestions
    case custom

    var id: String { rawValue }

    var title: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .login: "Login"
        case .note: "Secure Note"
        case .card: "Payment Card"
        case .identity: "Identity"
        case .sshKey: "SSH Key"
        case .recoveryCodes: "Recovery Codes"
        case .securityQuestions: "Security Questions"
        case .custom: "Custom"
        }
        return base.inAppLocalized
    }

    /// Polaris icon asset backing this category (chips, inline rows, pickers).
    var iconAsset: String {
        switch self {
        case .login: return "ic_globe"
        case .note: return "ic_note"
        case .card: return "ic_credit_card"
        case .identity: return "ic_identity_card"
        case .sshKey: return "ic_key"
        case .recoveryCodes: return "ic_refresh"
        case .securityQuestions: return "ic_question_circle"
        case .custom: return "ic_metafields"
        }
    }

    /// Duotone glyph used as the item's default AVATAR (type icon) — the modern
    /// two-tone look, tinted to the category color. Distinct from `iconAsset`,
    /// which stays single-tone for chips and inline rows.
    var avatarIcon: String {
        switch self {
        case .login: return "dt_globe"
        case .note: return "dt_note"
        case .card: return "dt_credit_card"
        case .identity: return "dt_id_card"
        case .sshKey: return "dt_key"
        case .recoveryCodes: return "dt_life_ring"
        case .securityQuestions: return "dt_question"
        case .custom: return "dt_shapes"
        }
    }

    /// Default fields used when creating a new item of this category. Labels are stored as
    /// stable English source strings (language-independent, so AutoFill stays kind-based and
    /// a later language switch still localizes correctly); the UI localizes them for display
    /// via the string catalog and passes user-authored labels through verbatim.
    var fieldTemplate: [DynamicField] {
        switch self {
        case .login:
            // Username + Password only. No Website and no One-time Code by default — the
            // Websites section starts as just an "Add Website" button (tapping it adds the
            // first field), and TOTP is added explicitly via Add Field (several allowed).
            // TOTP import appends its own totp field.
            return [
                DynamicField(label: "Username", kind: .username),
                DynamicField(label: "Password", kind: .password, protected: true),
            ]
        case .note:
            return [DynamicField(label: "Note", kind: .multiline)]
        case .card:
            return [
                DynamicField(label: "Cardholder", kind: .text),
                DynamicField(label: "Card Number", kind: .monospace, protected: true),
                DynamicField(label: "Expiry", kind: .text),
                DynamicField(label: "Security Code", kind: .monospace, protected: true),
                DynamicField(label: "PIN", kind: .number, protected: true),
            ]
        case .identity:
            return [
                DynamicField(label: "Full Name", kind: .text),
                DynamicField(label: "Email", kind: .email),
                DynamicField(label: "Phone", kind: .phone),
                DynamicField(label: "Address", kind: .multiline),
                DynamicField(label: "Date of Birth", kind: .date),
                DynamicField(label: "ID Number", kind: .monospace, protected: true),
            ]
        case .sshKey:
            return [
                DynamicField(label: "Private Key", kind: .multiline, protected: true),
                DynamicField(label: "Public Key", kind: .multiline),
            ]
        case .recoveryCodes:
            return [DynamicField(label: "Recovery Codes", kind: .multiline, protected: true)]
        case .securityQuestions:
            return [
                DynamicField(label: "Question 1", kind: .text),
                DynamicField(label: "Answer 1", kind: .text, protected: true),
                DynamicField(label: "Question 2", kind: .text),
                DynamicField(label: "Answer 2", kind: .text, protected: true),
            ]
        case .custom:
            return [DynamicField(label: "Field", kind: .text)]
        }
    }
}
