import AuthenticationServices
import SwiftUI
import UIKit

/// AutoFill Credential Provider entry point. Hosts a SwiftUI unlock + picker.
/// The vault is opened only after the user enters their master password
/// (Argon2id unwrap of the shared key bundle) — the same zero-knowledge model
/// as the main app. Passkeys are added in a later phase.
final class CredentialProviderViewController: ASCredentialProviderViewController {

    /// User tapped an item in our list / a saved credential is requested.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        showInterface(serviceIdentifiers: serviceIdentifiers.map(\.identifier), preferredRecordID: nil)
    }

    /// iOS asks us to provide a specific credential without showing UI. We always
    /// require the master password, so request that our UI be shown instead.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: ASCredentialRequest) {
        extensionContext.cancelRequest(
            withError: NSError(domain: ASExtensionErrorDomain,
                               code: ASExtensionError.Code.userInteractionRequired.rawValue))
    }

    /// iOS shows our UI to provide a specific credential (after the no-UI path).
    override func prepareInterfaceToProvideCredential(for credentialRequest: ASCredentialRequest) {
        let recordID = (credentialRequest.credentialIdentity as? ASPasswordCredentialIdentity)?.recordIdentifier
        showInterface(serviceIdentifiers: [], preferredRecordID: recordID)
    }

    // MARK: - Hosting

    private func showInterface(serviceIdentifiers: [String], preferredRecordID: String?) {
        let root = AutoFillView(
            serviceIdentifiers: serviceIdentifiers,
            preferredRecordID: preferredRecordID,
            onSelect: { [weak self] user, password in self?.complete(user: user, password: password) },
            onCancel: { [weak self] in self?.cancel() })

        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    private func complete(user: String, password: String) {
        extensionContext.completeRequest(
            withSelectedCredential: ASPasswordCredential(user: user, password: password))
    }

    private func cancel() {
        extensionContext.cancelRequest(
            withError: NSError(domain: ASExtensionErrorDomain,
                               code: ASExtensionError.Code.userCanceled.rawValue))
    }
}
