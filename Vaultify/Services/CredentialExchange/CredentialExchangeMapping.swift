#if compiler(>=6.2)
import AuthenticationServices
import CryptoKit
import Foundation

/// Maps Vaultify's vault models to and from the FIDO Credential Exchange value
/// tree (`ASExportedCredentialData`, iOS 26+). Bounded to the types that map
/// losslessly today — logins (basic auth), notes, and passkeys; other
/// categories are skipped and counted. Compiled only on Xcode with the iOS 26
/// SDK (`#if compiler(>=6.2)`), so it is absent from stable-Xcode CI builds.
///
/// UNVERIFIED across managers: `ASImportableCredential.Passkey.key` is an opaque
/// `Data` whose cross-provider encoding cannot be confirmed from the SDK. We use
/// PKCS#8 DER (`P256` round-trips it natively), which is lossless for Vaultify's
/// own export→import; interop with other managers needs iOS 26 device QA.
@available(iOS 26.1, *)
enum CredentialExchangeMapping {

    struct ImportResult {
        var items: [VaultItem] = []
        var passkeys: [PasskeySecret] = []
        var skipped: Int = 0
    }

    // MARK: Export

    static func exportData(items: [VaultItem], passkeys: [PasskeySecret],
                           exporterRelyingParty: String, exporterName: String,
                           now: Date = .now) -> ASExportedCredentialData {
        var importableItems = items.compactMap(importableItem)
        importableItems.append(contentsOf: passkeys.map(importableItem))
        let account = ASImportableAccount(
            id: newID(),
            userName: exporterName, email: "", fullName: nil,
            collections: [], items: importableItems)
        return ASExportedCredentialData(
            accounts: [account], formatVersion: .v1,
            exporterRelyingPartyIdentifier: exporterRelyingParty,
            exporterDisplayName: exporterName, timestamp: now)
    }

    private static func importableItem(_ source: VaultItem) -> ASImportableItem? {
        switch source.category {
        case .login:
            let user = source.usernameField?.value ?? ""
            let password = source.passwordField?.value ?? ""
            guard !user.isEmpty || !password.isEmpty else { return nil }
            let basic = ASImportableCredential.BasicAuthentication(
                userName: user.isEmpty ? nil : field(user, .string),
                password: password.isEmpty ? nil : field(password, .concealedString))
            return makeItem(source, credentials: [.basicAuthentication(basic)])
        case .note:
            let note = source.fields.first { $0.kind == .multiline || $0.kind == .text }?.value ?? ""
            guard !note.isEmpty else { return nil }
            let content: ASImportableEditableField = field(note, .string)
            let credential = ASImportableCredential.note(ASImportableCredential.Note(content: content))
            return makeItem(source, credentials: [credential])
        default:
            return nil
        }
    }

    private static func importableItem(_ secret: PasskeySecret) -> ASImportableItem {
        let passkey = ASImportableCredential.Passkey(
            credentialID: secret.credentialID,
            relyingPartyIdentifier: secret.relyingParty,
            userName: secret.userName,
            userDisplayName: secret.userName,
            userHandle: secret.userHandle,
            key: encodePasskeyKey(secret.privateKeyRaw) ?? Data())
        return ASImportableItem(
            id: newID(), title: secret.relyingParty, credentials: [.passkey(passkey)])
    }

    private static func makeItem(_ source: VaultItem, credentials: [ASImportableCredential]) -> ASImportableItem {
        ASImportableItem(id: newID(), title: source.title.isEmpty ? "Login" : source.title,
                         favorite: source.favorite, credentials: credentials, tags: source.tags)
    }

    /// Credential-exchange object ids are opaque 16-byte values (UUID bytes).
    private static func newID() -> Data {
        withUnsafeBytes(of: UUID().uuid) { Data($0) }
    }

    private static func field(_ value: String, _ type: ASImportableEditableField.FieldType) -> ASImportableEditableField {
        ASImportableEditableField(id: nil, fieldType: type, value: value)
    }

    // MARK: Import

    static func importResult(from data: ASExportedCredentialData) -> ImportResult {
        var result = ImportResult()
        for account in data.accounts {
            for item in account.items {
                var handled = false
                for credential in item.credentials {
                    switch credential {
                    case .passkey(let passkey):
                        if let secret = passkeySecret(passkey) { result.passkeys.append(secret); handled = true }
                    case .basicAuthentication(let basic):
                        result.items.append(loginItem(title: item.title, tags: item.tags, favorite: item.favorite, basic))
                        handled = true
                    case .note(let note):
                        result.items.append(noteItem(title: item.title, tags: item.tags, note.content.value))
                        handled = true
                    default:
                        break
                    }
                }
                if !handled { result.skipped += 1 }
            }
        }
        return result
    }

    private static func loginItem(title: String, tags: [String], favorite: Bool,
                                  _ basic: ASImportableCredential.BasicAuthentication) -> VaultItem {
        var fields: [DynamicField] = []
        if let user = basic.userName?.value, !user.isEmpty {
            fields.append(DynamicField(label: "field.username", kind: .username, value: user))
        }
        if let password = basic.password?.value, !password.isEmpty {
            fields.append(DynamicField(label: "field.password", kind: .password, value: password))
        }
        return VaultItem(category: .login, title: title.isEmpty ? "Imported Login" : title,
                         fields: fields, favorite: favorite, tags: tags)
    }

    private static func noteItem(title: String, tags: [String], _ content: String) -> VaultItem {
        VaultItem(category: .note, title: title.isEmpty ? "Imported Note" : title,
                  fields: [DynamicField(label: "field.note", kind: .multiline, value: content)], tags: tags)
    }

    private static func passkeySecret(_ passkey: ASImportableCredential.Passkey) -> PasskeySecret? {
        guard let raw = decodePasskeyKey(passkey.key) else { return nil }
        return PasskeySecret(relyingParty: passkey.relyingPartyIdentifier,
                             userName: passkey.userName,
                             userHandle: passkey.userHandle,
                             credentialID: passkey.credentialID,
                             privateKeyRaw: raw, counter: 0, createdAt: .now, flags: nil)
    }

    // MARK: Passkey key encoding (UNVERIFIED cross-manager — see type doc)

    static func encodePasskeyKey(_ privateKeyRaw: Data) -> Data? {
        (try? P256.Signing.PrivateKey(rawRepresentation: privateKeyRaw))?.derRepresentation
    }

    static func decodePasskeyKey(_ key: Data) -> Data? {
        if let der = try? P256.Signing.PrivateKey(derRepresentation: key) { return der.rawRepresentation }
        // Fallback: some managers may hand back the raw 32-byte scalar directly.
        if let raw = try? P256.Signing.PrivateKey(rawRepresentation: key) { return raw.rawRepresentation }
        return nil
    }
}
#endif
