import Foundation
import Security

/// Extracts certificate metadata from a PKCS#12 (`.p12`) signing identity.
/// The private key inside the archive is never copied, returned, or
/// persisted — only the certificate half is read, and any keychain footprint
/// the import could leave is deleted before returning.
nonisolated enum P12Inspector {
    static let maxInputBytes = 1024 * 1024

    struct Metadata: Equatable, Sendable {
        let commonName: String?
        /// Ten-character team identifier when the subject carries the Apple
        /// "Name (TEAMID)" convention.
        let teamID: String?
        let certificate: CertificateInspector.Result?
    }

    enum Outcome: Equatable, Sendable {
        case parsed(Metadata)
        case wrongPassphrase
        case unreadable
    }

    static func inspect(_ data: Data, passphrase: String) -> Outcome {
        guard data.count <= maxInputBytes else { return .unreadable }

        var options: [CFString: Any] = [kSecImportExportPassphrase: passphrase]
        if #available(iOS 18, *) {
            // Memory-only import is already iOS default behavior; stating it
            // makes the no-keychain-residue invariant explicit.
            options[kSecImportToMemoryOnly] = kCFBooleanTrue as Any
        }
        var rawItems: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &rawItems)
        switch status {
        case errSecSuccess:
            break
        case errSecAuthFailed, errSecPkcs12VerifyFailure:
            return .wrongPassphrase
        default:
            return .unreadable
        }
        guard let items = rawItems as? [[String: Any]],
              let identity = firstIdentity(in: items)
        else { return .unreadable }
        defer { deleteTransientKeychainItems(for: identity) }

        var certificateRef: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificateRef) == errSecSuccess,
              let certificate = certificateRef
        else { return .unreadable }

        let der = SecCertificateCopyData(certificate) as Data
        let details = CertificateInspector.inspect(der)

        var commonNameRef: CFString?
        var commonName: String?
        if SecCertificateCopyCommonName(certificate, &commonNameRef) == errSecSuccess,
           let name = commonNameRef as String? {
            commonName = Sanitize.displayString(name)
        } else {
            commonName = details?.subjectSummary
        }

        return .parsed(Metadata(commonName: commonName,
                                teamID: teamID(fromSubject: details?.subjectSummary),
                                certificate: details))
    }

    private static func firstIdentity(in items: [[String: Any]]) -> SecIdentity? {
        for item in items {
            guard let value = item[kSecImportItemIdentity as String] else { continue }
            let ref = value as CFTypeRef
            if CFGetTypeID(ref) == SecIdentityGetTypeID() {
                return (ref as! SecIdentity)
            }
        }
        return nil
    }

    /// Apple developer certificates put the team identifier in parentheses at
    /// the end of the subject, e.g. "Apple Distribution: Name (TEAMID)".
    private static func teamID(fromSubject subject: String?) -> String? {
        guard let subject,
              let match = subject.firstMatch(of: /\(([A-Z0-9]{10})\)/)
        else { return nil }
        return String(match.1)
    }

    /// iOS keeps PKCS#12 imports in process memory, but the invariant is too
    /// important to rest on documentation: delete any keychain item backing
    /// the imported identity, treating "not found" as the expected outcome.
    private static func deleteTransientKeychainItems(for identity: SecIdentity) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecMatchItemList: [identity] as CFArray,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
