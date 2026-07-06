import Foundation

/// Masks an email for overview surfaces: "chinh@gmail.com" → "ch***@gmail.com".
/// Keeps up to two leading characters of the local part so the user can
/// recognize the inbox, and the full domain (which is not the secret part).
/// The full address is only shown in explicit forwarding-inbox settings.
nonisolated enum EmailMask {
    static func masked(_ email: String) -> String {
        guard let at = email.firstIndex(of: "@"), at != email.startIndex else { return email }
        let prefix = email[..<at].prefix(2)
        return "\(prefix)***\(email[at...])"
    }
}
