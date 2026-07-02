#if compiler(>=6.2)
import AuthenticationServices
import Foundation

/// Drives the iOS 26 FIDO Credential Exchange managers. Export is app-initiated
/// (the OS shows the destination picker + biometric gate). Import is
/// system-initiated: iOS hands the app a token which we redeem for the payload.
///
/// PENDING iOS 26 device verification (see phase-07 discovery report): (1) how
/// the OS routes the import `token` to the app — the registering capability is
/// not derivable from the SDK headers; (2) cross-manager passkey key encoding.
@available(iOS 26.1, *)
@MainActor
enum CredentialExchangeService {
    struct ImportSummary { let imported: Int; let skipped: Int }

    static func export(items: [VaultItem], passkeys: [PasskeySecret],
                       anchor: ASPresentationAnchor) async throws {
        let manager = ASCredentialExportManager(presentationAnchor: anchor)
        _ = try await manager.requestExport()
        let data = CredentialExchangeMapping.exportData(
            items: items, passkeys: passkeys,
            exporterRelyingParty: "com.bervion.vaultify", exporterName: "Vaultify")
        try await manager.exportCredentials(data)
    }

    static func performImport(token: UUID, into repository: VaultRepository,
                              session: VaultSession, store: VaultStore) async throws -> ImportSummary {
        let data = try await ASCredentialImportManager().importCredentials(token: token)
        let mapped = CredentialExchangeMapping.importResult(from: data)
        for item in mapped.items { try repository.add(item) }
        if let key = session.vaultKey {
            let vault = PasskeyVault(store: store)
            for passkey in mapped.passkeys { _ = try vault.save(passkey, key: key) }
        }
        repository.reload()
        return ImportSummary(imported: mapped.items.count + mapped.passkeys.count, skipped: mapped.skipped)
    }
}
#endif
