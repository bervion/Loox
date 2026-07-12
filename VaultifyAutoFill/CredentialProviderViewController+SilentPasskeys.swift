import AuthenticationServices
import Foundation
import os

private let silentPasskeyLog = Logger(subsystem: "com.bervion.vaultify.autofill", category: "silent-passkey")

extension CredentialProviderViewController {
    @available(iOS 18, *)
    override func performWithoutUserInteractionIfPossible(passkeyRegistration request: ASPasskeyCredentialRequest) {
        Task { @MainActor in
            await performSilentPasskeyRegistration(request)
        }
    }

    @available(iOS 18, *)
    private func performSilentPasskeyRegistration(_ request: ASPasskeyCredentialRequest) async {
        guard SharedConfig.automaticPasskeyUpgradesEnabled else {
            skipSilentRegistration("toggle-off")
            return
        }
        guard request.supportedAlgorithms.contains(.ES256) else {
            skipSilentRegistration("algorithm")
            return
        }
        // The RP demands user verification; a silent creation cannot honestly
        // satisfy that (no ceremony runs), so hand back to the interactive flow
        // instead of registering a credential whose UV claim would be false.
        guard request.userVerificationPreference != .required else {
            skipSilentRegistration("uv-required")
            return
        }
        guard let publicKey = PasskeyEnvelope.publicKey() else {
            skipSilentRegistration("no-envelope-key")
            return
        }
        guard let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity,
              let store = makeStore() else {
            skipSilentRegistration("request")
            return
        }
        guard !hasExcludedCredential(request, store: store) else {
            skipSilentRegistration("excluded")
            return
        }

        let vault = PasskeyVault(store: store)
        var savedSecret: PasskeySecret?

        do {
            // No user was present or verified for this conditional creation — the
            // authenticator data must say so (UP=0, UV=0; BE/BS stay set).
            let registration = WebAuthn.register(relyingParty: identity.relyingPartyIdentifier,
                                                 flags: WebAuthn.conditionalCredentialFlags)
            let secret = PasskeySecret(relyingParty: identity.relyingPartyIdentifier,
                                       userName: identity.userName,
                                       userHandle: identity.userHandle,
                                       credentialID: registration.credentialID,
                                       privateKeyRaw: registration.privateKeyRaw,
                                       counter: 0,
                                       createdAt: .now,
                                       flags: registration.flags)
            let envelope = try PasskeyEnvelope.seal(secret, to: publicKey)
            try vault.saveEnvelope(secret, envelopeSealed: envelope)
            savedSecret = secret
            _ = try await saveSilentIdentity(secret)
            let credential = ASPasskeyRegistrationCredential(
                relyingParty: identity.relyingPartyIdentifier,
                clientDataHash: request.clientDataHash,
                credentialID: registration.credentialID,
                attestationObject: registration.attestationObject)
            silentPasskeyLog.log("silent-reg performed")
            await extensionContext.completeRegistrationRequest(using: credential)
        } catch {
            await rollbackSilentRegistration(savedSecret, vault: vault)
            silentPasskeyLog.error("silent-reg failed")
            cancel(code: .userInteractionRequired)
        }
    }

    @available(iOS 18, *)
    private func saveSilentIdentity(_ secret: PasskeySecret) async throws -> Bool {
        let store = ASCredentialIdentityStore.shared
        guard await store.state().isEnabled else { return false }
        try await store.saveCredentialIdentities([secret.credentialIdentity()])
        return true
    }

    @available(iOS 18, *)
    private func rollbackSilentRegistration(_ secret: PasskeySecret?, vault: PasskeyVault) async {
        guard let secret else { return }
        try? vault.delete(credentialID: secret.credentialID)
        try? await ASCredentialIdentityStore.shared.removeCredentialIdentities([secret.credentialIdentity()])
    }

    @available(iOS 18, *)
    private func skipSilentRegistration(_ reason: String) {
        silentPasskeyLog.log("silent-reg skipped(\(reason, privacy: .public))")
        cancel(code: .userInteractionRequired)
    }
}
