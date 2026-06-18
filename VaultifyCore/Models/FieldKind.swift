import Foundation

/// The kind of a dynamic field — drives keyboard, display, and protection.
nonisolated enum FieldKind: String, Codable, CaseIterable, Sendable {
    case text
    case username
    case password
    case totp
    case url
    case email
    case number
    case multiline
    case monospace
    case date
    case fileRef

    /// Whether values of this kind are encrypted at rest and masked in the UI by default.
    var defaultsProtected: Bool {
        switch self {
        case .password, .totp: return true
        default: return false
        }
    }

    var isMultiline: Bool { self == .multiline }

    /// Whether revealing the value should be a guarded (tap-to-show) interaction.
    var isSecret: Bool {
        switch self {
        case .password, .totp: return true
        default: return false
        }
    }

    var iconAsset: String {
        switch self {
        case .text: return "ic_text"
        case .username: return "ic_person"
        case .password: return "ic_lock"
        case .totp: return "ic_clock"
        case .url: return "ic_globe"
        case .email: return "ic_mail"
        case .number: return "ic_hashtag"
        case .multiline: return "ic_note"
        case .monospace: return "ic_metafields"
        case .date: return "ic_calendar"
        case .fileRef: return "ic_attachment"
        }
    }

    var title: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .text: "Text"
        case .username: "Username"
        case .password: "Password"
        case .totp: "One-time Code"
        case .url: "Website"
        case .email: "Email"
        case .number: "Number"
        case .multiline: "Note"
        case .monospace: "Monospace"
        case .date: "Date"
        case .fileRef: "Attachment"
        }
        return base.inAppLocalized
    }
}
