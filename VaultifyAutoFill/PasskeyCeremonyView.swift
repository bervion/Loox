import AuthenticationServices
import SwiftUI

struct PasskeyCeremonyView: View {
    let purpose: PasskeyPurpose
    let vaultKey: [UInt8]
    let store: VaultStore
    let onAssertion: (_ credential: ASPasskeyAssertionCredential) -> Void
    let onRegistration: (_ credential: ASPasskeyRegistrationCredential) -> Void
    let onCancel: (_ code: ASExtensionError.Code) -> Void

    @State private var matches: [PasskeyInfo] = []
    @State private var working = false
    @State private var errorMessage: String?
    @State private var didStartAssertion = false

    var body: some View {
        Form {
            switch purpose {
            case let .register(identity, _):
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
        guard case let .assert(relyingParty, allowed, _) = purpose, !didStartAssertion else { return }
        didStartAssertion = true
        let vault = PasskeyVault(store: store)
        matches = vault.matching(relyingParty: relyingParty, allowedCredentialIDs: allowed, key: vaultKey)
        switch matches.count {
        case 0:
            errorMessage = appString("No passkey for this site.")
            onCancel(.credentialIdentityNotFound)
        case 1:
            sign(matches[0])
        default:
            break
        }
    }

    private func createPasskey() {
        guard case let .register(identity, clientDataHash) = purpose else { return }
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
                let credential = ASPasskeyRegistrationCredential(
                    relyingParty: identity.relyingPartyIdentifier,
                    clientDataHash: clientDataHash,
                    credentialID: registration.credentialID,
                    attestationObject: registration.attestationObject)
                onRegistration(credential)
            } catch {
                errorMessage = appString("Couldn’t save the passkey.")
                onCancel(.failed)
            }
            working = false
        }
    }

    private func sign(_ info: PasskeyInfo) {
        guard case let .assert(relyingParty, _, clientDataHash) = purpose else { return }
        working = true; errorMessage = nil
        defer { working = false }
        do {
            guard let secret = PasskeyVault(store: store).secret(credentialID: info.credentialID, key: vaultKey) else {
                onCancel(.credentialIdentityNotFound)
                return
            }
            let result = try WebAuthn.assertion(relyingParty: relyingParty,
                                                clientDataHash: clientDataHash,
                                                privateKeyRaw: secret.privateKeyRaw,
                                                flags: secret.flags ?? WebAuthn.legacyAssertionFlags)
            PasskeyVault(store: store).touchLastUsed(credentialID: secret.credentialID)
            let credential = ASPasskeyAssertionCredential(
                userHandle: secret.userHandle,
                relyingParty: relyingParty,
                signature: result.signature,
                clientDataHash: clientDataHash,
                authenticatorData: result.authenticatorData,
                credentialID: secret.credentialID)
            onAssertion(credential)
        } catch {
            errorMessage = appString("Couldn’t sign in with this passkey.")
            onCancel(.failed)
        }
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
