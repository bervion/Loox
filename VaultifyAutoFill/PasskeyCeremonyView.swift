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
    /// askEachTime ceremony in flight — waiting for the owner's approval.
    @State private var awaitingApproval = false
    @State private var approvalTask: Task<Void, Never>?

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
                    if awaitingApproval {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Waiting for the owner to approve…")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Cancel", role: .cancel) {
                                approvalTask?.cancel()
                                onCancel(.userCanceled)
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
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
            // Shared passkey slots (capability v2): hand-over mode signs
            // locally after the live grant check. askEachTime slots await
            // the owner-approval ceremony — until that ships they fall back
            // to the password picker rather than a flash-error dismissal.
            let shared = sharedSlotMatches(relyingParty: relyingParty, allowed: allowed)
            if let handOver = shared.first(where: {
                $0.slot.mode == .shared && $0.slot.privateKeyRaw != nil
            }) {
                signShared(entry: handOver.entry, slot: handOver.slot)
            } else if let ask = shared.first(where: { $0.slot.mode == .askEachTime }) {
                startOwnerApproval(entry: ask.entry, slot: ask.slot)
            } else if let onNoPasskey {
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

    /// Shared passkey slots matching this assertion (rp + allow-list).
    private func sharedSlotMatches(relyingParty: String, allowed: [Data])
        -> [(entry: SharedCredentialEntry, slot: SharedPasskeyEntry)] {
        SharedCredentialsCache.load(vaultKey: vaultKey).flatMap { entry in
            (entry.passkeys ?? []).compactMap { slot in
                guard slot.relyingParty == relyingParty,
                      allowed.isEmpty || allowed.contains(slot.credentialID) else { return nil }
                return (entry, slot)
            }
        }
    }

    /// Hand-over mode: sign locally with the delivered key — but only after
    /// the authoritative live grant check passes (INV-11; online-required).
    /// Failures keep the sheet up with a message instead of flash-dismissing.
    private func signShared(entry: SharedCredentialEntry, slot: SharedPasskeyEntry) {
        guard case let .assert(relyingParty, _, clientDataHash, _) = purpose,
              let keyRaw = slot.privateKeyRaw else { return }
        working = true
        Task {
            let outcome = await SharedGrantLiveCheck.verify(
                zoneName: entry.zoneName, ownerName: entry.ownerName,
                expectedGrantId: entry.grantId)
            working = false
            switch outcome {
            case .revoked:
                errorMessage = appString("The owner has revoked access to this item.")
                return
            case .unavailable:
                errorMessage = appString("Couldn't verify access right now.")
                return
            case .authorized:
                break
            }
            do {
                let result = try WebAuthn.assertion(
                    relyingParty: relyingParty, clientDataHash: clientDataHash,
                    privateKeyRaw: keyRaw,
                    flags: slot.flags ?? WebAuthn.legacyAssertionFlags)
                onAssertion(ASPasskeyAssertionCredential(
                    userHandle: slot.userHandle, relyingParty: relyingParty,
                    signature: result.signature, clientDataHash: clientDataHash,
                    authenticatorData: result.authenticatorData,
                    credentialID: slot.credentialID))
            } catch {
                errorMessage = appString("Couldn’t sign in with this passkey.")
            }
        }
    }

    /// askEachTime: the private key stays with the owner (INV-07) — submit a
    /// signed, challenge-bound request and wait for the sealed assertion.
    /// Every failure keeps the sheet up with a message; Cancel is always
    /// available while waiting.
    private func startOwnerApproval(entry: SharedCredentialEntry, slot: SharedPasskeyEntry) {
        guard case let .assert(relyingParty, _, clientDataHash, _) = purpose else { return }
        awaitingApproval = true
        errorMessage = nil
        approvalTask = Task {
            do {
                let ticket = try await PasskeyApprovalTransport.submitRequest(
                    zoneName: entry.zoneName, ownerName: entry.ownerName,
                    expectedGrantId: entry.grantId, slotId: slot.slotId,
                    clientDataHash: clientDataHash)
                let payload = try await PasskeyApprovalTransport.awaitApproval(ticket)
                awaitingApproval = false
                onAssertion(ASPasskeyAssertionCredential(
                    userHandle: payload.userHandle, relyingParty: relyingParty,
                    signature: payload.signature, clientDataHash: clientDataHash,
                    authenticatorData: payload.authenticatorData,
                    credentialID: payload.credentialID))
            } catch is CancellationError {
                awaitingApproval = false
            } catch PasskeyApprovalTransport.Failure.rejected {
                awaitingApproval = false
                errorMessage = appString("The owner declined this sign-in.")
            } catch PasskeyApprovalTransport.Failure.timedOut {
                awaitingApproval = false
                errorMessage = appString("No answer from the owner yet. Try again in a moment.")
            } catch {
                awaitingApproval = false
                errorMessage = appString("Couldn't reach the owner right now.")
            }
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
