import AuthenticationServices
import SwiftUI

enum PasskeyPurpose {
    case assert(relyingParty: String, allowedCredentialIDs: [Data], clientDataHash: Data)
    case register(identity: ASPasskeyCredentialIdentity, clientDataHash: Data)
}

/// Passkey entry point: shared Face ID / master-password gate, then the
/// post-unlock ceremony UI.
struct PasskeyActionView: View {
    let title: LocalizedStringKey
    let purpose: PasskeyPurpose
    let store: VaultStore
    let onAssertion: (_ credential: ASPasskeyAssertionCredential) -> Void
    let onRegistration: (_ credential: ASPasskeyRegistrationCredential) -> Void
    let onCancel: (_ code: ASExtensionError.Code) -> Void

    var body: some View {
        UnlockGate(title: title, onCancel: { onCancel(.userCanceled) }) { vaultKey in
            PasskeyMigrationGate(vaultKey: vaultKey, store: store) {
                PasskeyCeremonyView(purpose: purpose,
                                    vaultKey: vaultKey,
                                    store: store,
                                    onAssertion: onAssertion,
                                    onRegistration: onRegistration,
                                    onCancel: onCancel)
            }
        }
    }
}

private struct PasskeyMigrationGate<Content: View>: View {
    let vaultKey: [UInt8]
    let store: VaultStore
    @ViewBuilder var content: () -> Content
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                content()
            } else {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await prepare() }
    }

    private func prepare() async {
        let result = PasskeyVault(store: store).prepareEnvelopeOnUnlock(key: vaultKey)
        if !result.quarantinedSites.isEmpty {
            SharedConfig.queuePasskeyQuarantineNotice(sites: result.quarantinedSites)
        }
        let replaced = result.replaced.map { $0.credentialIdentity() }
        if !result.quarantinedIdentities.isEmpty || !replaced.isEmpty {
            let identities = result.quarantinedIdentities.map { $0.credentialIdentity() } + replaced
            try? await ASCredentialIdentityStore.shared.removeCredentialIdentities(identities)
        }
        ready = true
    }
}
