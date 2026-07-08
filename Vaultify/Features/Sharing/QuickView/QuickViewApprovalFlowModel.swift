import CryptoKit
import Foundation
import LocalAuthentication

/// Owner-side Quick View ceremony state machine: resolve the scanned/typed
/// code → verify the signed session envelope → show the SAS for the owner to
/// eyeball → Face ID → re-read the item → compose → seal → upload. Item
/// choice is always the one the app already has open — never named by the
/// browser/server.
@MainActor @Observable final class QuickViewApprovalFlowModel {

    enum State: Equatable {
        case idle
        case resolving
        case verified(VerifiedSession)
        case approving
        case done
        case error(String)
    }

    /// Everything the approval sheet needs once a session verifies.
    struct VerifiedSession: Equatable {
        let sessionID: String
        /// `sessionID` hex-decoded — every crypto/transcript call site (seal,
        /// AAD, upload assertion) binds these raw bytes, never the hex
        /// string's own UTF-8 bytes.
        let sessionIDBytes: Data
        let sas: String
        let browserEncPublicKey: Data
        let browserEncKeyHash: Data
        let browserSigKeyHash: Data
        let env: String
        /// Absolute deadline (Unix ms) for the approval upload — also bounds
        /// the TOTP boundary wait in the composer.
        let expiresAtUnixMs: Int64
    }

    /// `internal(set)` (not `private`) so tests can drive a `.verified` state
    /// directly without a live network resolve — production call sites
    /// (views, `resolve`/`approve`) all live in this module too, so this
    /// doesn't widen access outside it.
    internal(set) var state: State = .idle
    /// Mutated live by the approval sheet's toggles; read only when the
    /// ceremony actually runs — never cached before that.
    var selectedFieldIDs: Set<String>
    var includeCurrentTOTP = false

    let itemID: String
    private let api: QuickViewAPIClient
    private let repository: VaultRepository
    private let history: QuickViewHistoryStore
    /// Optional-capability breaker sink (INV-CAP-03: one per service, never
    /// shared) — weak + optional so tests without a `CapabilityStore` run
    /// unchanged; an outage here never touches the core vault.
    weak var capabilities: CapabilityStore?
    /// Resolves the SESSION-V1 signer's endorsed public key (DEC-QV-SIGN-01)
    /// — weak + optional so tests can drive `.verified` directly without a
    /// live signer-keyset fetch; a `nil` keyset (not yet fetched) makes
    /// EVERY session fail verification, never a silent trust bypass.
    weak var signerKeyset: QuickViewSignerKeysetClient?

    init(itemID: String, defaultSelectedFieldIDs: Set<String>, repository: VaultRepository,
        history: QuickViewHistoryStore, api: QuickViewAPIClient = QuickViewAPIClient(),
        capabilities: CapabilityStore? = nil, signerKeyset: QuickViewSignerKeysetClient? = nil) {
        self.itemID = itemID
        self.selectedFieldIDs = defaultSelectedFieldIDs
        self.repository = repository
        self.history = history
        self.api = api
        self.capabilities = capabilities
        self.signerKeyset = signerKeyset
    }

    private var genericErrorMessage: String { appString("Start again on the computer.") }

    /// Classify an API failure for the capability store: verified operator
    /// state persists; infra failures feed the breaker; everything else means
    /// the service answered (INV-CAP-07 — no state change from generic errors).
    private func note(_ error: Error) {
        switch error {
        case QuickViewAPIError.capability(let mode, let retryAfter):
            capabilities?.noteOperatorSignal(.quickView, .init(mode: mode, retryAfter: retryAfter))
        case QuickViewAPIError.server(let status, _) where (502...504).contains(status):
            capabilities?.noteInfrastructureFailure(.quickView)
        case is URLError:
            capabilities?.noteInfrastructureFailure(.quickView)
        default:
            capabilities?.noteServiceResponded(.quickView)
        }
    }

    /// Resolve a scanned QR value or a typed human code — both paths share
    /// this one call. A QR "variant B" payload (`LOOX-QV-QR-V1:...`) carries
    /// a compact locator PLUS a signed-session digest; a plain typed code
    /// has no digest to check. Either way the server resolves the extracted
    /// code as an opaque locator.
    func resolve(code: String) async {
        state = .resolving
        let qr = QuickViewQRCode.parse(code)
        let locator = qr?.humanCode ?? code
        guard capabilities?.allowRequest(.quickView) ?? true else {
            state = .error(genericErrorMessage)
            return
        }
        do {
            let resolved = try await api.resolve(code: locator)
            capabilities?.noteSuccess(.quickView)
            let encHash = Data(SHA256.hash(data: resolved.browserEncPublicKey))
            let sigHash = Data(SHA256.hash(data: resolved.browserSigPublicKey))
            let envelope = try QuickViewSessionEnvelopeVerifier.verify(
                envelopeData: resolved.envelopeData,
                resolveSignerKey: { [weak signerKeyset] keyID in signerKeyset?.resolveSignerKey(keyID: keyID) },
                expectedEnv: QuickViewConfig.environment,
                expectedEncKeyHash: encHash, expectedSigKeyHash: sigHash)
            // Bind the resolved session back to what was SCANNED — a QR that
            // resolved to a different session than the one on screen is a
            // hard fail, no bypass (same discipline as the SAS mismatch abort).
            if let qr {
                let actualDigest = QuickViewQRCode.digest(
                    sessionIDBytes: envelope.sessionIDBytes, encKeyHash: envelope.encKeyHash,
                    sigKeyHash: envelope.sigKeyHash)
                guard actualDigest == qr.digest else {
                    state = .error(genericErrorMessage)
                    return
                }
            }
            guard let sas = QuickViewSAS.derive(sessionID: envelope.sessionIDBytes,
                                                encKeyHash: envelope.encKeyHash,
                                                sigKeyHash: envelope.sigKeyHash) else {
                state = .error(genericErrorMessage)
                return
            }
            state = .verified(VerifiedSession(
                sessionID: envelope.sessionID, sessionIDBytes: envelope.sessionIDBytes, sas: sas,
                browserEncPublicKey: resolved.browserEncPublicKey,
                browserEncKeyHash: envelope.encKeyHash, browserSigKeyHash: envelope.sigKeyHash,
                env: envelope.env, expiresAtUnixMs: envelope.expiresAt))
            // Advisory bind — spinner-free, never awaited by the UI, failure ignored.
            Task { [api] in
                let assertion = await QuickViewAttestation.assertBind(api: api, sessionID: envelope.sessionID)
                await api.bindAdvisory(sessionID: envelope.sessionID, assertion: assertion)
            }
        } catch {
            note(error)
            state = .error(genericErrorMessage)
        }
    }

    /// SAS mismatch — hard abort, no "continue anyway" exists in the UI that
    /// calls this.
    func abortSASMismatch() {
        history.record(itemID: itemID, result: .cancelled)
        state = .idle
    }

    func cancel() {
        history.record(itemID: itemID, result: .cancelled)
        state = .idle
    }

    /// Face ID → re-read the item (never a copy taken before the prompt) →
    /// compose → seal → upload.
    func approve() async {
        guard case .verified(let session) = state else { return }
        state = .approving
        do {
            guard repository.item(id: itemID) != nil else {
                state = .error(genericErrorMessage)
                return
            }
            try await BiometricAuth.authenticate(
                reason: appString("Approve sending fields to your browser"))
            guard let freshItem = repository.item(id: itemID) else {
                state = .error(genericErrorMessage)
                return
            }
            let composed = try await QuickViewPayloadComposer.compose(
                item: freshItem, selectedFieldIDs: selectedFieldIDs,
                includeCurrentTOTP: includeCurrentTOTP,
                sessionExpiresAtUnixMs: session.expiresAtUnixMs)

            // 32 random bytes — NOT a UUID string: the AAD transcript binds
            // `approval_id` as raw bytes (frozen vector), never UTF-8.
            let approvalID = CryptoRandom.data(32)
            let issuedAt = Int64(Date().timeIntervalSince1970 * 1000)
            let expiresAt = issuedAt + Int64(QuickViewConfig.approvalUploadTTLSeconds * 1000)

            let sealed = try QuickViewPayloadSealer.seal(
                plaintext: composed.payloadPlaintext, browserEncPublicKey: session.browserEncPublicKey,
                browserEncKeyHash: session.browserEncKeyHash, browserSigKeyHash: session.browserSigKeyHash,
                sessionID: session.sessionIDBytes, env: session.env, approvalID: approvalID,
                fieldManifestHash: composed.fieldManifestHash, issuedAt: issuedAt, expiresAt: expiresAt)

            let aadBytes = QuickViewPayloadSealer.aad(
                sessionID: session.sessionIDBytes, encKeyHash: session.browserEncKeyHash, approvalID: approvalID,
                fieldManifestHash: composed.fieldManifestHash, issuedAt: issuedAt, expiresAt: expiresAt)
            let uploadBody = QuickViewCanonical.canonicalUploadBody(
                aad: aadBytes, ciphertext: sealed.ciphertext, appEphemeralPublicKey: sealed.appEphemeralPublicKey)
            let assertion = await QuickViewAttestation.assertUpload(
                api: api, sessionID: session.sessionID, sessionIDBytes: session.sessionIDBytes,
                uploadBody: uploadBody)

            try await api.upload(
                sessionID: session.sessionID, ciphertext: sealed.ciphertext,
                appEphemeralPublicKey: sealed.appEphemeralPublicKey,
                aad: aadBytes,   // the exact AAD the sealer authenticated + the assertion covers
                assertion: assertion)
            capabilities?.noteSuccess(.quickView)

            history.record(itemID: itemID, result: .completed)
            state = .done
        } catch let error as LAError where error.code == .userCancel || error.code == .systemCancel
            || error.code == .appCancel {
            history.record(itemID: itemID, result: .cancelled)
            state = .idle
        } catch {
            // Composer/network/crypto errors all read the same calm, generic
            // way — never a state-specific branch (plan.md failure discipline).
            note(error)
            history.record(itemID: itemID, result: .failed)
            state = .error(genericErrorMessage)
        }
    }
}
