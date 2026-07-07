import Foundation

/// Orchestrates the Loox Link quick-share flow: build the plaintext envelope
/// from the owner's field selection → AES-256-GCM encrypt ON DEVICE → prove
/// app genuineness (App Attest, when the hardware supports it) → upload only
/// the ciphertext → mint the share URL with the content key in the fragment.
/// The server never sees a plaintext field or the key; revocation stores only
/// an opaque token.
@MainActor @Observable final class LooxLinkService {
    let records = LooxLinkRecordStore()
    private let api = LooxLinkAPIClient()
    /// Optional-capability state sink — independent from Private Email's
    /// (INV-CAP-03). Optional so tests without an AppEnvironment run unchanged.
    weak var capabilities: CapabilityStore?

    struct CreatedLink {
        let url: URL
        let record: LooxLinkRecord
    }

    enum Failure: LocalizedError {
        case nothingSelected
        case tooLarge
        case badServerData

        var errorDescription: String? {
            switch self {
            case .nothingSelected: appString("Select at least one field to share.")
            case .tooLarge: appString("This item is too large to share as a link.")
            case .badServerData: appString("The share service sent an unexpected response.")
            }
        }
    }

    func createLink(item: VaultItem, selectedFieldIDs: Set<String>,
                    expirySeconds: UInt64, oneTime: Bool = false) async throws -> CreatedLink {
        let envelope = LooxLinkEnvelope.build(item: item, selectedFieldIDs: selectedFieldIDs)
        guard !envelope.fields.isEmpty else { throw Failure.nothingSelected }
        let expiry = min(expirySeconds, LooxLinkConfig.maxExpirySeconds)

        let plaintext = try envelope.encoded()
        let cipher = try LooxLinkCrypto.encrypt(plaintext)
        // The wire body is ~4/3 of the raw ciphertext; bound early so the user
        // gets a clear message instead of a server 413.
        guard cipher.ciphertextB64.utf8.count < LooxLinkConfig.maxBodyBytes - 512 else {
            throw Failure.tooLarge
        }

        // App Attest on real devices. Shadow phase (server ASSERTION_MODE
        // off/shadow): attest best-effort — a failure logs and the interim
        // token still authenticates, because the assertion isn't the auth
        // yet and a register bug must not brick creation. Once the server
        // requires assertions, `attestationRequired` makes failures BLOCK
        // the create (C6 fail-closed, no unauthenticated fallback).
        var assertion: LooxLinkAPIClient.AssertionHeaders?
        if LooxLinkConfig.attestationEnabled, LooxLinkAttestation.isSupported {
            do {
                assertion = try await LooxLinkAttestation.assertCreateShare(
                    api: api, ciphertext: cipher.ciphertextRaw, iv: cipher.ivRaw,
                    expiresInSeconds: expiry, oneTime: oneTime)
            } catch {
                if LooxLinkConfig.attestationRequired { throw error }
                #if DEBUG
                print("[LooxLink] attest failed (shadow mode, continuing with token): \(error)")
                #endif
            }
        }

        guard capabilities?.allowRequest(.shareLink) ?? true else {
            throw LooxLinkAPIError.capability(.active, retryAfter: nil)   // breaker open → "temporarily unavailable"
        }
        let response: LooxLinkCreateResponse
        do {
            response = try await api.createShare(
                ciphertextB64: cipher.ciphertextB64, ivB64: cipher.ivB64,
                expiresInSeconds: expiry, oneTime: oneTime, assertion: assertion)
            capabilities?.noteSuccess(.shareLink)
        } catch {
            note(error)
            throw error
        }
        guard let url = LooxLinkConfig.shareURL(shareId: response.shareId,
                                                fragmentKey: cipher.fragmentKey,
                                                oneTime: oneTime) else {
            throw Failure.badServerData
        }

        let record = LooxLinkRecord(
            shareId: response.shareId, revokeToken: response.revokeToken,
            itemId: item.id, createdAt: .now,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(response.expiresAt)),
            oneTime: oneTime)
        records.add(record)
        return CreatedLink(url: url, record: record)
    }

    /// Revoke server-side, then forget locally. A 404 means the link is
    /// already gone (expired/revoked) — treat that as success and clean up.
    func revoke(_ record: LooxLinkRecord) async throws {
        do {
            try await api.revoke(shareId: record.shareId, revokeToken: record.revokeToken)
            capabilities?.noteSuccess(.shareLink)
        } catch LooxLinkAPIError.notFound {
            // Already dead server-side — fall through to local cleanup.
            capabilities?.noteServiceResponded(.shareLink)
        } catch {
            note(error)
            throw error
        }
        records.remove(shareId: record.shareId)
    }

    /// Classify an API failure for the capability store: verified operator
    /// state persists; infra failures feed the breaker; everything else means
    /// the service answered (INV-CAP-07 — no state change from generic errors).
    private func note(_ error: Error) {
        switch error {
        case LooxLinkAPIError.capability(let mode, let retryAfter):
            capabilities?.noteOperatorSignal(.shareLink, .init(mode: mode, retryAfter: retryAfter))
        case LooxLinkAPIError.server(let status, _) where (502...504).contains(status):
            capabilities?.noteInfrastructureFailure(.shareLink)
        case is URLError:
            capabilities?.noteInfrastructureFailure(.shareLink)
        default:
            capabilities?.noteServiceResponded(.shareLink)
        }
    }
}
