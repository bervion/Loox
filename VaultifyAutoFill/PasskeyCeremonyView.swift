import AuthenticationServices
import SwiftUI

struct PasskeyCeremonyView: View {
    let purpose: PasskeyPurpose
    let vaultKey: SecureBytes
    let store: VaultStore
    let onAssertion: (_ credential: ASPasskeyAssertionCredential) -> Void
    let onRegistration: (_ credential: ASPasskeyRegistrationCredential) -> Void
    let onCancel: (_ code: ASExtensionError.Code) -> Void
    /// QuickType-list assertions set this: a site can request a passkey while
    /// the user only holds a password (e.g. a credential SHARED to them) — the
    /// right answer is the password picker, not an error that dismisses the
    /// sheet. The unlocked key rides along so the picker skips a second Face ID.
    var onNoPasskey: ((_ vaultKey: SecureBytes) -> Void)? = nil

    @State private var matches: [PasskeyInfo] = []
    @State private var working = false
    @State private var errorMessage: String?
    @State private var didStartAssertion = false
    /// askEachTime ceremony in flight — waiting for the owner's approval.
    @State private var awaitingApproval = false
    @State private var approvalTask: Task<Void, Never>?
    /// Seconds left in the polling budget, so a timeout is a countdown the
    /// user watched rather than a surprise.
    @State private var secondsLeft = 0
    /// Terminal state of a SHARED passkey attempt (either mode). Never nil
    /// while the sheet sits idle after a failure — a shared-passkey dead end
    /// with no way forward and no way out is the bug this replaces.
    @State private var sharedOutcome: SharedOutcome?

    /// What the recipient is told after a shared-passkey attempt ended, plus
    /// the action that can still change the result. `retry` nil means trying
    /// again cannot help, so the only honest affordance is the way out.
    private struct SharedOutcome {
        let message: String
        var retryTitle: LocalizedStringKey = "Try Again"
        var retry: (() -> Void)?
    }

    /// The owner has this long to answer before the extension gives up
    /// (`SharedAccessTimingPolicy.extensionPollingBudget`). Stated in the UI
    /// so the wait has a visible end.
    private static let approvalBudgetSeconds =
        Int(SharedAccessTimingPolicy.standard.extensionPollingBudget.components.seconds)

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
        .task(id: awaitingApproval) { await runWaitCountdown() }
    }

    /// Ticks the visible countdown while an approval is outstanding. Purely a
    /// display clock — the transport owns the real deadline.
    private func runWaitCountdown() async {
        guard awaitingApproval else { return }
        var remaining = Self.approvalBudgetSeconds
        while awaitingApproval, remaining > 0 {
            secondsLeft = remaining
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            remaining -= 1
        }
        secondsLeft = 0
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
                    if let sharedOutcome {
                        outcomeView(sharedOutcome)
                    } else if awaitingApproval {
                        waitingView
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

    /// The wait states what has to happen on the OTHER device, because that
    /// is the only thing that ends it: the owner opens Loox, unlocks, and
    /// approves. Without that sentence a timeout reads as a broken app.
    private var waitingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Waiting for the owner to approve…")
                .font(.footnote)
            Text("They have to open Loox and approve with Face ID.")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if secondsLeft > 0 {
                Text("About \(secondsLeft) seconds left")
                    .font(.footnote).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button("Cancel", role: .cancel) {
                approvalTask?.cancel()
                onCancel(.userCanceled)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
    }

    private func outcomeView(_ outcome: SharedOutcome) -> some View {
        VStack(spacing: 12) {
            Text(verbatim: outcome.message)
                .font(.footnote).foregroundStyle(.red)
                .multilineTextAlignment(.center)
            if let retry = outcome.retry {
                Button(outcome.retryTitle) {
                    sharedOutcome = nil
                    retry()
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel", role: .cancel) { onCancel(.userCanceled) }
                    .buttonStyle(.bordered)
            } else {
                // Nothing here can succeed on a second try, so the way out is
                // the only action and takes the primary rank.
                Button("Cancel", role: .cancel) { onCancel(.userCanceled) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func startAssertionIfNeeded() {
        guard case let .assert(relyingParty, allowed, _, _) = purpose, !didStartAssertion else { return }
        didStartAssertion = true
        let vault = PasskeyVault(store: store)
        matches = vault.matching(relyingParty: relyingParty, allowedCredentialIDs: allowed, key: vaultKey)
        switch matches.count {
        case 0:
            // Shared passkey slots (capability v2): hand-over mode signs
            // locally after the live grant check; askEachTime runs the
            // owner-approval ceremony in this extension. Only when neither
            // applies does the sheet fall back to the password picker.
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
        sharedOutcome = nil
        Task {
            let outcome = await SharedGrantLiveCheck.verify(
                zoneName: entry.zoneName, ownerName: entry.ownerName,
                expectedGrantId: entry.grantId)
            working = false
            switch outcome {
            case .revoked:
                // Authorization is gone for good — a retry would only fail again.
                sharedOutcome = SharedOutcome(
                    message: appString("The owner has revoked access to this item."))
                return
            case .unavailable:
                // Fail-closed, but not necessarily final: the check could not
                // reach iCloud, which a second attempt often can.
                sharedOutcome = SharedOutcome(
                    message: appString("Couldn't verify access right now. Check your connection."),
                    retry: { signShared(entry: entry, slot: slot) })
                return
            case .authorized:
                break
            }
            do {
                // Per-ceremony flags: this assertion runs behind the unlock gate
                // plus the live grant check, so UP/UV are true regardless of the
                // stored registration flags (which only contribute BE/BS).
                let result = try WebAuthn.assertion(
                    relyingParty: relyingParty, clientDataHash: clientDataHash,
                    privateKeyRaw: keyRaw,
                    flags: WebAuthn.assertionFlags(stored: slot.flags))
                onAssertion(ASPasskeyAssertionCredential(
                    userHandle: slot.userHandle, relyingParty: relyingParty,
                    signature: result.signature, clientDataHash: clientDataHash,
                    authenticatorData: result.authenticatorData,
                    credentialID: slot.credentialID))
            } catch {
                sharedOutcome = SharedOutcome(
                    message: appString("Couldn’t sign in with this passkey."))
            }
        }
    }

    /// askEachTime: the private key stays with the owner (INV-07) — submit a
    /// signed, challenge-bound request and wait for the sealed assertion.
    /// Every ending is a state the user can act on: Cancel while waiting, and
    /// a named cause plus a retry (where a retry can help) once it ends.
    private func startOwnerApproval(entry: SharedCredentialEntry, slot: SharedPasskeyEntry) {
        guard case let .assert(relyingParty, _, clientDataHash, _) = purpose else { return }
        awaitingApproval = true
        errorMessage = nil
        sharedOutcome = nil
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
            } catch {
                awaitingApproval = false
                sharedOutcome = Self.outcome(for: error) {
                    startOwnerApproval(entry: entry, slot: slot)
                }
            }
        }
    }

    /// Honest cause-by-cause reading of an approval failure. Only `.rejected`
    /// and `.interrupted` mean the owner actually saw the request — every
    /// other case failed before or after their device was involved, so none of
    /// them may imply the owner made a choice, and a case that a second
    /// attempt cannot change offers no retry.
    private static func outcome(for error: any Error,
                                retry: @escaping () -> Void) -> SharedOutcome {
        let askAgain: LocalizedStringKey = "Ask Again"
        switch error {
        case PasskeyApprovalTransport.Failure.rejected:
            return SharedOutcome(message: appString("The owner declined this sign-in."),
                                 retryTitle: askAgain, retry: retry)
        case PasskeyApprovalTransport.Failure.interrupted:
            return SharedOutcome(
                message: appString("The owner started to approve, then Loox closed on their device."),
                retryTitle: askAgain, retry: retry)
        case PasskeyApprovalTransport.Failure.timedOut:
            return SharedOutcome(
                message: appString("No answer from the owner. They may not have Loox open."),
                retryTitle: askAgain, retry: retry)
        case PasskeyApprovalTransport.Failure.grantUnavailable:
            // The grant fetch is also the online gate, so this is either a
            // revoked share or a dead connection — say both, offer both.
            return SharedOutcome(
                message: appString("Couldn't load this share. It may have been revoked, or you may be offline."),
                retry: retry)
        case PasskeyApprovalTransport.Failure.capabilityNotGranted:
            return SharedOutcome(message: appString("This passkey isn't shared with you anymore."))
        case PasskeyApprovalTransport.Failure.invalidResponse:
            return SharedOutcome(message: appString("The owner's answer couldn't be verified."),
                                 retryTitle: askAgain, retry: retry)
        case PasskeyApprovalTransport.Failure.notConfigured:
            return SharedOutcome(message: appString("iCloud sharing isn't available in this version of Loox."))
        default:
            // CloudKit / network: the request may never have left this device,
            // so it must not claim the owner was reached.
            return SharedOutcome(message: appString("Couldn't reach iCloud. Check your connection."),
                                 retry: retry)
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
            // Per-ceremony flags: assertions always run behind the unlock gate, so
            // UP/UV are true even for a conditionally created credential whose
            // registration recorded UP=0/UV=0; stored flags only contribute BE/BS.
            let result = try WebAuthn.assertion(relyingParty: relyingParty,
                                                clientDataHash: clientDataHash,
                                                privateKeyRaw: secret.privateKeyRaw,
                                                flags: WebAuthn.assertionFlags(stored: secret.flags))
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
