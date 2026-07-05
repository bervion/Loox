import AuthenticationServices
import SwiftUI

struct PasskeyCeremonyView: View {
    let purpose: PasskeyPurpose
    let vaultKey: [UInt8]
    let store: VaultStore
    let onAssertion: (_ credential: ASPasskeyAssertionCredential) -> Void
    let onRegistration: (_ credential: ASPasskeyRegistrationCredential) -> Void
    let onCancel: (_ code: ASExtensionError.Code) -> Void
    /// QuickType-list assertions set this: a site can request a passkey while
    /// the user only holds a password (e.g. a credential SHARED to them) — the
    /// right answer is the password picker, not an error that dismisses the
    /// sheet. The unlocked key rides along so the picker skips a second Face ID.
    var onNoPasskey: ((_ vaultKey: [UInt8]) -> Void)? = nil

    @State private var matches: [PasskeyInfo] = []
    @State private var working = false
    @State private var errorMessage: String?
    @State private var didStartAssertion = false

    var body: some View {
        Form {
            switch purpose {
            case let .register(identity, _, _):
                registrationSection(identity: identity)
            case .assert:
                assertionSection
            }
        }
        .overlay { if working { ProgressView().controlSize(.large) } }
        .disabled(working)
        .task { startAssertionIfNeeded() }
    }

    private func registrationSection(identity: ASPasskeyCredentialIdentity) -> some View {
        Group {
            Section {
                LabeledContent("Website", value: identity.relyingPartyIdentifier)
                LabeledContent("Username", value: identity.userName)
            } footer: {
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                Button(action: createPasskey) {
                    HStack { Spacer(); Text("Create Passkey").bold(); Spacer() }
                }
            }
        }
    }

    private var assertionSection: some View {
        Group {
            if matches.count > 1 {
                Section {
                    ForEach(matches) { info in
                        Button { sign(info) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(info.userName).font(.body)
                                    Text(info.lastUsedAt ?? info.createdAt, style: .relative)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                    }
                } header: {
                    Text("Choose a passkey")
                } footer: {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
            } else {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } footer: {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                }
            }
        }
    }

    private func startAssertionIfNeeded() {
        guard case let .assert(relyingParty, allowed, _, _) = purpose, !didStartAssertion else { return }
        didStartAssertion = true
        let vault = PasskeyVault(store: store)
        matches = vault.matching(relyingParty: relyingParty, allowedCredentialIDs: allowed, key: vaultKey)
        switch matches.count {
        case 0:
            if let onNoPasskey {
                onNoPasskey(vaultKey)
            } else {
                errorMessage = appString("No passkey for this site.")
                onCancel(.credentialIdentityNotFound)
            }
        case 1:
            sign(matches[0])
        default:
            break
        }
    }

    private func createPasskey() {
        guard case let .register(identity, clientDataHash, _) = purpose else { return }
        working = true; errorMessage = nil
        Task {
            do {
                let registration = WebAuthn.register(relyingParty: identity.relyingPartyIdentifier)
                let secret = PasskeySecret(relyingParty: identity.relyingPartyIdentifier,
                                           userName: identity.userName,
                                           userHandle: identity.userHandle,
                                           credentialID: registration.credentialID,
                                           privateKeyRaw: registration.privateKeyRaw,
                                           counter: 0,
                                           createdAt: .now,
                                           flags: registration.flags)
                let result = try PasskeyVault(store: store).save(secret, key: vaultKey)
                try await syncRegistrationIdentity(new: secret, replaced: result.replaced)
                onRegistration(registrationCredential(identity: identity,
                                                      clientDataHash: clientDataHash,
                                                      registration: registration))
            } catch {
                errorMessage = appString("Couldn’t save the passkey.")
                onCancel(.failed)
            }
            working = false
        }
    }

    private func sign(_ info: PasskeyInfo) {
        guard case let .assert(relyingParty, _, clientDataHash, _) = purpose else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do {
            let vault = PasskeyVault(store: store)
            guard let secret = vault.secret(credentialID: info.credentialID, key: vaultKey) else {
                onCancel(.credentialIdentityNotFound)
                return
            }
            let result = try WebAuthn.assertion(relyingParty: relyingParty,
                                                clientDataHash: clientDataHash,
                                                privateKeyRaw: secret.privateKeyRaw,
                                                flags: secret.flags ?? WebAuthn.legacyAssertionFlags)
            vault.touchLastUsed(credentialID: secret.credentialID)
            onAssertion(assertionCredential(secret: secret, result: result,
                                            relyingParty: relyingParty,
                                            clientDataHash: clientDataHash, vault: vault))
        } catch {
            errorMessage = appString("Couldn’t sign in with this passkey.")
            onCancel(.failed)
        }
    }

    /// Registration credential, advertising largeBlob support when the RP asked (iOS 18+).
    private func registrationCredential(identity: ASPasskeyCredentialIdentity,
                                        clientDataHash: Data,
                                        registration: WebAuthn.Registration) -> ASPasskeyRegistrationCredential {
        if #available(iOS 18, *), case .registerSupport = purpose.largeBlob {
            return ASPasskeyRegistrationCredential(
                relyingParty: identity.relyingPartyIdentifier,
                clientDataHash: clientDataHash,
                credentialID: registration.credentialID,
                attestationObject: registration.attestationObject,
                extensionOutput: PasskeyLargeBlob.registrationOutput(supported: true))
        }
        return ASPasskeyRegistrationCredential(
            relyingParty: identity.relyingPartyIdentifier,
            clientDataHash: clientDataHash,
            credentialID: registration.credentialID,
            attestationObject: registration.attestationObject)
    }

    /// Assertion credential, servicing a largeBlob read/write when requested (iOS 18+).
    private func assertionCredential(secret: PasskeySecret,
                                     result: (authenticatorData: Data, signature: Data),
                                     relyingParty: String, clientDataHash: Data,
                                     vault: PasskeyVault) -> ASPasskeyAssertionCredential {
        if #available(iOS 18, *) {
            switch purpose.largeBlob {
            case .read:
                let blob = vault.largeBlob(credentialID: secret.credentialID, key: vaultKey)
                return assertion(secret, result, relyingParty, clientDataHash,
                                 output: PasskeyLargeBlob.assertionReadOutput(blob))
            case .write(let data):
                let ok = vault.setLargeBlob(data, credentialID: secret.credentialID, key: vaultKey)
                return assertion(secret, result, relyingParty, clientDataHash,
                                 output: PasskeyLargeBlob.assertionWriteOutput(success: ok))
            case .none, .registerSupport:
                break
            }
        }
        return ASPasskeyAssertionCredential(
            userHandle: secret.userHandle, relyingParty: relyingParty,
            signature: result.signature, clientDataHash: clientDataHash,
            authenticatorData: result.authenticatorData, credentialID: secret.credentialID)
    }

    @available(iOS 18, *)
    private func assertion(_ secret: PasskeySecret,
                           _ result: (authenticatorData: Data, signature: Data),
                           _ relyingParty: String, _ clientDataHash: Data,
                           output: ASPasskeyAssertionCredentialExtensionOutput) -> ASPasskeyAssertionCredential {
        ASPasskeyAssertionCredential(
            userHandle: secret.userHandle, relyingParty: relyingParty,
            signature: result.signature, clientDataHash: clientDataHash,
            authenticatorData: result.authenticatorData, credentialID: secret.credentialID,
            extensionOutput: output)
    }

    private func syncRegistrationIdentity(new: PasskeySecret, replaced: [PasskeySecret]) async throws {
        let identityStore = ASCredentialIdentityStore.shared
        guard await identityStore.state().isEnabled else { return }
        let oldIdentities = replaced.map { $0.credentialIdentity() }
        if !oldIdentities.isEmpty {
            try await identityStore.removeCredentialIdentities(oldIdentities)
        }
        try await identityStore.saveCredentialIdentities([new.credentialIdentity()])
    }
}
