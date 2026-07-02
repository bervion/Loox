import AuthenticationServices
import Foundation

extension PasskeyInfo {
    /// Shared identity-store mapping. `recordIdentifier` mirrors the record id:
    /// base64url credentialID, so pre-unlock checks can match without secrets.
    func credentialIdentity() -> ASPasskeyCredentialIdentity {
        ASPasskeyCredentialIdentity(
            relyingPartyIdentifier: relyingParty,
            userName: userName,
            credentialID: credentialID,
            userHandle: userHandle,
            recordIdentifier: recordIdentifier)
    }
}

extension PasskeySecret {
    func credentialIdentity() -> ASPasskeyCredentialIdentity {
        info.credentialIdentity()
    }
}
