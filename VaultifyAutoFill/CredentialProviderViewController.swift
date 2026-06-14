import AuthenticationServices
import SwiftUI
import UIKit

/// AutoFill Credential Provider entry point. Hosts a SwiftUI unlock + picker.
/// The vault is opened only after the user enters their master password
/// (Argon2id unwrap of the shared key bundle) — the same zero-knowledge model
/// as the main app. Provides both passwords and passkeys.
final class CredentialProviderViewController: ASCredentialProviderViewController {

    private enum PasskeyPurpose {
        case assert(relyingParty: String, allowedCredentialIDs: [Data], clientDataHash: Data)
        case register(identity: ASPasskeyCredentialIdentity, clientDataHash: Data)
    }

    // MARK: Passwords

    /// User picks from our list / a saved credential is requested.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        host(AutoFillView(serviceIdentifiers: serviceIdentifiers.map(\.identifier),
                          preferredRecordID: nil,
                          onSelect: { [weak self] user, password in self?.complete(user: user, password: password) },
                          onCancel: { [weak self] in self?.cancel() }))
    }

    /// iOS asks us to provide a credential without UI. We always require the
    /// master password, so request that our UI be shown instead.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
        extensionContext.cancelRequest(
            withError: NSError(domain: ASExtensionErrorDomain,
                               code: ASExtensionError.Code.userInteractionRequired.rawValue))
    }

    /// iOS shows our UI to provide a specific credential (password or passkey).
    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
        if let passkey = credentialRequest as? ASPasskeyCredentialRequest,
           let identity = passkey.credentialIdentity as? ASPasskeyCredentialIdentity {
            showPasskey(.assert(relyingParty: identity.relyingPartyIdentifier,
                                allowedCredentialIDs: [identity.credentialID],
                                clientDataHash: passkey.clientDataHash))
        } else {
            let recordID = (credentialRequest.credentialIdentity as? ASPasswordCredentialIdentity)?.recordIdentifier
            host(AutoFillView(serviceIdentifiers: [], preferredRecordID: recordID,
                              onSelect: { [weak self] user, password in self?.complete(user: user, password: password) },
                              onCancel: { [weak self] in self?.cancel() }))
        }
    }

    // MARK: Passkeys

    /// Passkey registration ceremony (create a new credential).
    override func prepareInterface(forPasskeyRegistration registrationRequest: ASCredentialRequest) {
        guard let request = registrationRequest as? ASPasskeyCredentialRequest,
              let identity = request.credentialIdentity as? ASPasskeyCredentialIdentity else { cancel(); return }
        showPasskey(.register(identity: identity, clientDataHash: request.clientDataHash))
    }

    /// Passkey assertion invoked from the QuickType bar.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier],
                                        requestParameters: ASPasskeyCredentialRequestParameters) {
        showPasskey(.assert(relyingParty: requestParameters.relyingPartyIdentifier,
                            allowedCredentialIDs: requestParameters.allowedCredentials,
                            clientDataHash: requestParameters.clientDataHash))
    }

    private func showPasskey(_ purpose: PasskeyPurpose) {
        let prompt: LocalizedStringResource
        if case .register = purpose { prompt = "Create a passkey" } else { prompt = "Sign in with a passkey" }
        host(PasskeyActionView(prompt: prompt,
                               onUnlocked: { [weak self] key in self?.perform(purpose, vaultKey: key) },
                               onCancel: { [weak self] in self?.cancel() }))
    }

    private func perform(_ purpose: PasskeyPurpose, vaultKey: [UInt8]) {
        switch purpose {
        case let .assert(relyingParty, allowed, clientDataHash):
            let matches = PasskeyVault.matching(relyingParty: relyingParty, allowedCredentialIDs: allowed, key: vaultKey)
            guard let passkey = matches.first,
                  let result = try? WebAuthn.assertion(relyingParty: relyingParty,
                                                       clientDataHash: clientDataHash,
                                                       privateKeyRaw: passkey.privateKeyRaw) else {
                cancel(code: .credentialIdentityNotFound); return
            }
            let credential = ASPasskeyAssertionCredential(
                userHandle: passkey.userHandle, relyingParty: relyingParty,
                signature: result.signature, clientDataHash: clientDataHash,
                authenticatorData: result.authenticatorData, credentialID: passkey.credentialID)
            extensionContext.completeAssertionRequest(using: credential)

        case let .register(identity, clientDataHash):
            let registration = WebAuthn.register(relyingParty: identity.relyingPartyIdentifier)
            let secret = PasskeySecret(relyingParty: identity.relyingPartyIdentifier,
                                       userName: identity.userName, userHandle: identity.userHandle,
                                       credentialID: registration.credentialID,
                                       privateKeyRaw: registration.privateKeyRaw, counter: 0, createdAt: .now)
            try? PasskeyVault.save(secret, key: vaultKey)
            let credential = ASPasskeyRegistrationCredential(
                relyingParty: identity.relyingPartyIdentifier, clientDataHash: clientDataHash,
                credentialID: registration.credentialID, attestationObject: registration.attestationObject)
            extensionContext.completeRegistrationRequest(using: credential)
        }
    }

    // MARK: Hosting & completion

    private func host(_ rootView: some View) {
        // Apply the user's theme (shared via the App Group) so the extension matches
        // the app: accent tint + light/dark. Static — no wallpaper/animation here.
        let theme = ThemePalette.resolve(
            ThemeReader.load(),
            systemIsDark: traitCollection.userInterfaceStyle == .dark,
            brightness: 1.0)
        let hosting = UIHostingController(
            rootView: rootView
                .tint(Color(rgb: theme.accent))
                .preferredColorScheme(theme.isDark ? .dark : .light))
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    private func complete(user: String, password: String) {
        extensionContext.completeRequest(
            withSelectedCredential: ASPasswordCredential(user: user, password: password))
    }

    private func cancel(code: ASExtensionError.Code = .userCanceled) {
        extensionContext.cancelRequest(
            withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }
}
