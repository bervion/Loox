import AuthenticationServices
import SwiftUI
import UIKit
import os

/// Diagnostic logger for the AutoFill extension. Filter in Console.app by the
/// subsystem to trace which entry points iOS actually invokes. Non-sensitive
/// markers only — never log usernames, passwords, or vault contents.
private let autofillLog = Logger(subsystem: "com.bervion.vaultify.autofill", category: "lifecycle")

/// AutoFill Credential Provider entry point. Hosts a SwiftUI unlock + picker.
/// The vault is opened only after the user enters their master password
/// (Argon2id unwrap of the shared key bundle) — the same zero-knowledge model
/// as the main app. Provides both passwords and passkeys.
final class CredentialProviderViewController: ASCredentialProviderViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        autofillLog.log("viewDidLoad")
        // Localize the extension UI against the in-app language (mirrored into the App Group by
        // the app) rather than the device locale — set before any SwiftUI Text renders.
        appResourceLocale = appLocale(
            forCode: SharedConfig.sharedDefaults.string(forKey: SharedConfig.languageKey) ?? "system")
    }

    private enum PasskeyPurpose {
        case assert(relyingParty: String, allowedCredentialIDs: [Data], clientDataHash: Data)
        case register(identity: ASPasskeyCredentialIdentity, clientDataHash: Data)
    }

    // MARK: Passwords

    /// User picks from our list / a saved credential is requested.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        autofillLog.log("prepareCredentialList(passwords) services=\(serviceIdentifiers.count, privacy: .public)")
        host(AutoFillView(serviceIdentifiers: serviceIdentifiers.map(\.identifier),
                          preferredRecordID: nil,
                          onSelect: { [weak self] user, password in self?.complete(user: user, password: password) },
                          onCancel: { [weak self] in self?.cancel() }))
    }

    /// User taps a 2FA / one-time-code field and picks Vaultify — show our TOTP picker.
    @available(iOS 18, *)
    override func prepareOneTimeCodeCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        autofillLog.log("prepareOneTimeCodeCredentialList services=\(serviceIdentifiers.count, privacy: .public)")
        host(OneTimeCodeView(serviceIdentifiers: serviceIdentifiers.map(\.identifier),
                             preferredRecordID: nil,
                             onSelect: { [weak self] code in self?.completeOneTimeCode(code) },
                             onCancel: { [weak self] in self?.cancel() }))
    }

    @available(iOS 18, *)
    private func completeOneTimeCode(_ code: String) {
        extensionContext.completeOneTimeCodeRequest(using: ASOneTimeCodeCredential(code: code))
    }

    /// iOS asks us to provide a credential without UI. Unlock is ALWAYS interactive (Face ID
    /// or master password) — even with a biometric key now reachable, never silently fill.
    /// Must keep returning `userInteractionRequired` so our UI (and its auth gate) is shown.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
        autofillLog.log("provideCredentialWithoutUserInteraction → userInteractionRequired")
        extensionContext.cancelRequest(
            withError: NSError(domain: ASExtensionErrorDomain,
                               code: ASExtensionError.Code.userInteractionRequired.rawValue))
    }

    /// iOS shows our UI to provide a specific credential (password, passkey, or 2FA code).
    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
        autofillLog.log("prepareInterfaceToProvideCredential")
        if #available(iOS 18, *), let otp = credentialRequest as? ASOneTimeCodeCredentialRequest {
            let recordID = (otp.credentialIdentity as? ASOneTimeCodeCredentialIdentity)?.recordIdentifier
            host(OneTimeCodeView(serviceIdentifiers: [], preferredRecordID: recordID,
                                 onSelect: { [weak self] code in self?.completeOneTimeCode(code) },
                                 onCancel: { [weak self] in self?.cancel() }))
            return
        }
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

    // MARK: Save & generate (iOS 26.2+ native AutoFill)

    #if compiler(>=6.2)
    /// iOS asks to SAVE a credential the user just created on a web form (the native
    /// "Save password in Vaultify" sheet). We host a confirm-and-unlock UI, then seal it
    /// into the vault. iOS 26.2+ only; older iOS uses the manual "＋ Create new login" flow.
    @available(iOS 26.2, *)
    override func prepareInterface(for savePasswordRequest: ASSavePasswordRequest) {
        autofillLog.log("prepareInterface(save) event=\(savePasswordRequest.event.rawValue, privacy: .public)")
        // Skip the premature "strong password just filled" event — the credential has no
        // username/email yet. The real save lands at form submission (see below).
        guard savePasswordRequest.event != .generatedPasswordFilled else {
            extensionContext.completeSavePasswordRequest(completionHandler: nil)
            return
        }
        let credential = savePasswordRequest.credential
        host(SavePasswordView(
            host: savePasswordRequest.serviceIdentifier.identifier,
            username: credential.user,
            password: credential.password,
            onSaved: { [weak self] in self?.extensionContext.completeSavePasswordRequest(completionHandler: nil) },
            onCancel: { [weak self] in self?.cancel() }))
    }

    /// iOS asks whether we can save silently. The vault is locked (need Face ID / master
    /// password), so for a real save we request interactive UI. EXCEPTION: the
    /// `generatedPasswordFilled` event fires right after the strong password is inserted, before
    /// the user types their email — that credential is incomplete, so we complete without a
    /// prompt and let the proper save happen at form submission (`formDidDisappear` /
    /// `userInitiated`), when the username/email is present.
    @available(iOS 26.2, *)
    override func performWithoutUserInteractionIfPossible(savePasswordRequest: ASSavePasswordRequest) {
        if savePasswordRequest.event == .generatedPasswordFilled {
            autofillLog.log("performSave(noUI) generatedPasswordFilled → skip (incomplete credential)")
            extensionContext.completeSavePasswordRequest(completionHandler: nil)
            return
        }
        autofillLog.log("performSave(noUI) event=\(savePasswordRequest.event.rawValue, privacy: .public) → userInteractionRequired")
        cancel(code: .userInteractionRequired)
    }

    /// Branded "Use Strong Password" generation. Needs no vault key, so return a strong
    /// password headlessly (the OS presents it); `SupportsGeneratePasswordCredentialsWithUI=false`.
    @available(iOS 26.2, *)
    override func performWithoutUserInteraction(generatePasswordsRequest: ASGeneratePasswordsRequest) {
        autofillLog.log("performGenerate(noUI)")
        let result = ASGeneratedPassword(kind: .strong, value: PasswordGenerator.generate(PasswordOptions()))
        extensionContext.completeGeneratePasswordRequest(results: [result], completionHandler: nil)
    }
    #endif

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
        autofillLog.log("host: presenting SwiftUI content")
        // Apply the user's theme (shared via the App Group) so the extension matches
        // the app: accent tint + light/dark. Static — no wallpaper/animation here.
        let theme = ThemePalette.resolve(
            ThemeReader.load(),
            systemIsDark: traitCollection.userInterfaceStyle == .dark,
            brightness: 1.0)
        let hosting = UIHostingController(
            rootView: rootView
                .tint(Color(rgb: theme.accent))
                .preferredColorScheme(theme.isDark ? .dark : .light)
                // Resolve SwiftUI `Text("…")` literals against the in-app language (mirrored from
                // the app via the App Group) — the environment locale selects the catalog table,
                // which the bare literals otherwise read from the device locale.
                .environment(\.locale, appResourceLocale))
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
