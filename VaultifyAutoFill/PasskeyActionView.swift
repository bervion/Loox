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
            PasskeyCeremonyView(purpose: purpose,
                                vaultKey: vaultKey,
                                store: store,
                                onAssertion: onAssertion,
                                onRegistration: onRegistration,
                                onCancel: onCancel)
        }
    }
}
