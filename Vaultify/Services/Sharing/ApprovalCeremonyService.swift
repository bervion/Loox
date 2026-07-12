import CloudKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The owner's approve/reject ceremony (ADR-1 + ADR-6). Everything here runs
/// foreground-only with an unlocked vault:
///
///   OWNER_APPROVED → CHECK_TOTP_WINDOW
///     ├─ remaining ≥ policy.minimumRemainingLifetime → ISSUE_NOW
///     └─ remaining <  policy.minimumRemainingLifetime → WAITING_FOR_FRESH_WINDOW
///          → (boundary reached, still foreground + unlocked) → ISSUE_NOW
///
/// NEVER pre-sends a future-period code: a TOTP for counter N+1 is not
/// delivered while trusted local time is still in counter N — the wait ends
/// AT the boundary and the then-current code is generated. During the wait
/// the seed is NOT read (timing math only); if the app backgrounds or the
/// vault locks mid-wait, issuance ABORTS with a signed `interrupted` so the
/// requester is told to ask again instead of waiting on nothing.
@MainActor @Observable final class ApprovalCeremonyService {
    enum CeremonyState: Equatable {
        case idle
        case authenticating
        case waitingForFreshWindow(boundaryUnixMs: Int64, periodSeconds: UInt32)
        case issuing
        case finished(ApprovalDecision)
        case failed(String)
    }

    private(set) var state: CeremonyState = .idle

    private let session: VaultSession
    private let repository: VaultRepository
    private let shareService: ApprovalShareService
    /// Passkey approvals read the secret straight from the passkey store.
    private let store: VaultStore
    private let policy = TOTPIssuancePolicy.v1

    init(session: VaultSession, repository: VaultRepository,
         shareService: ApprovalShareService, store: VaultStore) {
        self.session = session
        self.repository = repository
        self.shareService = shareService
        self.store = store
    }

    private var nowUnixMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// Foreground + unlocked — re-checked at every hop that matters.
    /// `!= .background` (not `== .active`): Face ID's system overlay drives
    /// the app `.inactive`, which must not read as "user left".
    private var ceremonyConditionsHold: Bool {
        guard session.state == .unlocked else { return false }
        #if canImport(UIKit)
        return UIApplication.shared.applicationState != .background
        #else
        return true
        #endif
    }

    // MARK: Approve

    /// Face ID → authoritative verify (consumes the nonce) → boundary-aware
    /// issuance → seal to the request's ephemeral key → signed response.
    func approve(_ pending: ApprovalCoordinator.PendingOwnerRequest) async {
        // Passkey slots take the assertion path (no TOTP window mechanics);
        // both share the same verify-then-Face-ID discipline.
        if PasskeySlot.isPasskeySlot(pending.request.fieldId) {
            await approvePasskey(pending)
            return
        }
        guard state == .idle || stateIsTerminal else { return } // no concurrent ceremonies
        let request = pending.request
        let zoneID = CKRecordZone.ID(zoneName: pending.zoneName)
        state = .authenticating
        do {
            // 1. User presence. Face ID/passcode via the existing helper.
            try await BiometricAuth.authenticate(
                reason: appString("Approve a verification-code request"))
            guard ceremonyConditionsHold else { return abort(request, zoneID: zoneID) }

            // 2. Authoritative verification — pinned key, fresh grant/epoch,
            // lifetime, and the SINGLE-USE nonce burn (H4) happen here.
            _ = try await shareService.verifyInbound(request, zoneID: zoneID, nowUnixMs: nowUnixMs)
            // The CloudKit await can resume after a background transition
            // (with lock-on-background off the cache would still be warm) —
            // re-check before ANY seed material is touched.
            guard ceremonyConditionsHold else { return abort(request, zoneID: zoneID) }

            // 3. Timing math only — the field value is read inside a throwaway
            // scope to parse the period and is NOT retained across any wait
            // (ADR-6: no seed caching; the issue-time read happens fresh below).
            guard let period: UInt32 = ({
                guard let item = repository.item(id: request.itemId),
                      let field = item.fields.first(where: { $0.id == request.fieldId }),
                      field.kind == .totp else { return nil }
                return Self.period(forStoredValue: field.value)
            }()) else {
                state = .failed(appString("This code isn't available anymore."))
                sendInterrupted(request, zoneID: zoneID)
                return
            }

            // 4. Boundary-aware window gate (ADR-6) as a LOOP: a late wake
            // from a suspended sleep re-evaluates instead of issuing below
            // the freshness budget.
            while !policy.canIssueNow(atUnixMs: nowUnixMs, period: period) {
                let boundary = TOTPWindow.periodEndUnixMs(atUnixMs: nowUnixMs, period: period)
                state = .waitingForFreshWindow(boundaryUnixMs: boundary, periodSeconds: period)
                let waitMs = boundary - nowUnixMs
                if waitMs > 0 {
                    try await Task.sleep(for: .milliseconds(waitMs))
                }
                guard ceremonyConditionsHold else { return abort(request, zoneID: zoneID) }
            }

            // 5. ISSUE_NOW: fresh seed read (fails closed if the vault locked
            // meanwhile — the repository cache is emptied on lock) → generate
            // the now-current code → full window-context payload (ADR-7) →
            // seal → respond.
            state = .issuing
            let issuedAtMs = nowUnixMs
            guard let item = repository.item(id: request.itemId),
                  let field = item.fields.first(where: { $0.id == request.fieldId }),
                  field.kind == .totp,
                  let code = TOTPGenerator.code(
                      forStoredValue: field.value,
                      date: Date(timeIntervalSince1970: Double(issuedAtMs) / 1000)) else {
                state = .failed(appString("This code isn't available anymore."))
                sendInterrupted(request, zoneID: zoneID)
                return
            }
            let payload = TOTPApprovalPayload(
                code: code,
                counter: TOTPWindow.counter(atUnixMs: issuedAtMs, period: period),
                period: period,
                generatedAtUnixMs: issuedAtMs,
                periodStartUnixMs: TOTPWindow.periodStartUnixMs(atUnixMs: issuedAtMs, period: period),
                periodEndUnixMs: TOTPWindow.periodEndUnixMs(atUnixMs: issuedAtMs, period: period),
                requestNonce: request.nonce)
            var plaintext = try JSONEncoder().encode(payload)
            defer { plaintext.resetBytes(in: 0..<plaintext.count) } // zero temp buffer
            let sealed = try ApprovalSeal.sealResponsePayload(
                plaintext, toEphemeralPubKey: request.ephemeralPubKey,
                requestId: request.requestId, nonce: request.nonce)
            try await shareService.respond(requestId: request.requestId, decision: .approved,
                                           sealedPayload: sealed, zoneID: zoneID,
                                           nowUnixMs: nowUnixMs)
            state = .finished(.approved)
        } catch is CancellationError {
            abort(request, zoneID: zoneID)
        } catch {
            // The nonce may already be burnt — tell the requester to stop
            // waiting (their retry supersedes this request, Phase 6).
            state = .failed(error.localizedDescription)
            sendInterrupted(request, zoneID: zoneID)
        }
    }

    /// Passkey askEachTime approval (INV-07: the private key never leaves
    /// this device — only the signed assertion does). Face ID → authoritative
    /// verify (burns the nonce; the verifier already enforced the 32-byte
    /// clientDataHash binding for passkey slots) → sign the requester's exact
    /// challenge → seal to the request's ephemeral key (forward secrecy,
    /// requestId + nonce in the HPKE info — INV-09) → signed response.
    private func approvePasskey(_ pending: ApprovalCoordinator.PendingOwnerRequest) async {
        guard state == .idle || stateIsTerminal else { return }
        let request = pending.request
        let zoneID = CKRecordZone.ID(zoneName: pending.zoneName)
        state = .authenticating
        do {
            try await BiometricAuth.authenticate(
                reason: appString("Approve a sign-in request"))
            guard ceremonyConditionsHold else { return abort(request, zoneID: zoneID) }
            _ = try await shareService.verifyInbound(request, zoneID: zoneID, nowUnixMs: nowUnixMs)
            guard ceremonyConditionsHold else { return abort(request, zoneID: zoneID) }

            state = .issuing
            guard let binding = request.payloadBinding,
                  let credentialID = PasskeySlot.credentialID(fromSlotId: request.fieldId),
                  let vaultKey = session.vaultKey,
                  let secret = PasskeyVault(store: store).secret(credentialID: credentialID,
                                                                 key: vaultKey) else {
                state = .failed(appString("This passkey isn't available anymore."))
                sendInterrupted(request, zoneID: zoneID)
                return
            }
            let result = try WebAuthn.assertion(
                relyingParty: secret.relyingParty, clientDataHash: binding,
                privateKeyRaw: secret.privateKeyRaw,
                flags: WebAuthn.assertionFlags(stored: secret.flags))
            let payload = PasskeyApprovalPayload(
                authenticatorData: result.authenticatorData,
                signature: result.signature,
                userHandle: secret.userHandle,
                credentialID: secret.credentialID,
                clientDataHash: binding,
                requestNonce: request.nonce)
            let sealed = try ApprovalSeal.sealResponsePayload(
                try JSONEncoder().encode(payload),
                toEphemeralPubKey: request.ephemeralPubKey,
                requestId: request.requestId, nonce: request.nonce)
            try await shareService.respond(requestId: request.requestId, decision: .approved,
                                           sealedPayload: sealed, zoneID: zoneID,
                                           nowUnixMs: nowUnixMs)
            state = .finished(.approved)
        } catch is CancellationError {
            abort(request, zoneID: zoneID)
        } catch {
            state = .failed(error.localizedDescription)
            sendInterrupted(request, zoneID: zoneID)
        }
    }

    /// The sheet is being closed while the ceremony is mid-flight — the user
    /// abandoned it. Abort per ADR-6 (never continue headless).
    func abandonIfBusy(_ pending: ApprovalCoordinator.PendingOwnerRequest) {
        switch state {
        case .authenticating, .waitingForFreshWindow, .issuing:
            abort(pending.request, zoneID: CKRecordZone.ID(zoneName: pending.zoneName))
        default:
            break
        }
    }

    /// One-tap signed reject so the requester stops waiting immediately.
    func reject(_ pending: ApprovalCoordinator.PendingOwnerRequest) async {
        guard state == .idle || stateIsTerminal else { return }
        let zoneID = CKRecordZone.ID(zoneName: pending.zoneName)
        do {
            try await shareService.respond(requestId: pending.request.requestId,
                                           decision: .rejected, sealedPayload: nil,
                                           zoneID: zoneID, nowUnixMs: nowUnixMs)
            state = .finished(.rejected)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func resetState() { state = .idle }

    private var stateIsTerminal: Bool {
        if case .finished = state { return true }
        if case .failed = state { return true }
        return false
    }

    /// ADR-6 abort: background/lock/abandon mid-ceremony → tell B, never continue.
    private func abort(_ request: ApprovalRequest, zoneID: CKRecordZone.ID) {
        state = .failed(appString("Approval was interrupted. Ask them to request again."))
        sendInterrupted(request, zoneID: zoneID)
    }

    /// Best-effort signed `interrupted` so the requester stops waiting (their
    /// "Request again" supersedes this request on the Phase-6 side).
    private func sendInterrupted(_ request: ApprovalRequest, zoneID: CKRecordZone.ID) {
        Task { [shareService] in
            try? await shareService.respond(requestId: request.requestId, decision: .interrupted,
                                            sealedPayload: nil, zoneID: zoneID,
                                            nowUnixMs: Int64(Date().timeIntervalSince1970 * 1000))
        }
    }

    /// Period from a stored TOTP value (otpauth URI or bare base32 → 30s).
    private static func period(forStoredValue value: String) -> UInt32 {
        if value.lowercased().hasPrefix("otpauth://"),
           let cfg = TOTPGenerator.parse(uri: value), cfg.period > 0 {
            return UInt32(cfg.period)
        }
        return 30
    }
}
