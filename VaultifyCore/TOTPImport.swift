import Foundation

/// Builds a draft login item from an `otpauth://` 2FA setup URL (opened via a link or QR scan when
/// Vaultify is the system's "Set Up Verification Codes" provider). Pure — also unit-testable.
nonisolated enum TOTPImport {
    /// A new (unsaved) `.login` item pre-filled with the issuer (title), account (username) and the
    /// full `otpauth://` URI in the TOTP field. Returns nil for non-otpauth or malformed URLs.
    static func draftLogin(from url: URL) -> VaultItem? {
        guard url.scheme?.lowercased() == "otpauth",
              TOTPGenerator.parse(uri: url.absoluteString) != nil else { return nil }

        // Label is the path: "Issuer:account" or just "account". The issuer query param wins.
        let rawLabel = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let label = rawLabel.removingPercentEncoding ?? rawLabel
        let parts = label.split(separator: ":", maxSplits: 1).map(String.init)
        let issuerParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "issuer" }?.value?.removingPercentEncoding
        let issuer = (issuerParam ?? (parts.count == 2 ? parts[0] : "")).trimmingCharacters(in: .whitespaces)
        let account = (parts.count == 2 ? parts[1] : label).trimmingCharacters(in: .whitespaces)

        var fields = ItemCategory.login.fieldTemplate
        if let i = fields.firstIndex(where: { $0.kind == .username }) { fields[i].value = account }
        if let i = fields.firstIndex(where: { $0.kind == .totp }) { fields[i].value = url.absoluteString }

        // Issuer is the natural title; fall back to the account. If both are empty (rare malformed
        // label) leave it blank — the user names it in the editor before saving.
        let title = issuer.isEmpty ? account : issuer
        return VaultItem(category: .login, title: title, fields: fields)
    }
}
