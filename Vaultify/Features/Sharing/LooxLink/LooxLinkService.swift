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

        // App Attest gates creation where the hardware supports it (real
        // device) once the backend ships verification (see
        // `LooxLinkConfig.attestationEnabled`). Until then the interim
        // `X-Loox-App-Token` header is the create auth.
        var assertion: LooxLinkAPIClient.AssertionHeaders?
        if LooxLinkConfig.attestationEnabled, LooxLinkAttestation.isSupported {
            assertion = try await LooxLinkAttestation.assertCreateShare(
                api: api, ciphertext: cipher.ciphertextRaw, iv: cipher.ivRaw,
                expiresInSeconds: expiry)
        }

        let response = try await api.createShare(
            ciphertextB64: cipher.ciphertextB64, ivB64: cipher.ivB64,
            expiresInSeconds: expiry, oneTime: oneTime, assertion: assertion)
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
        } catch LooxLinkAPIError.notFound {
            // Already dead server-side — fall through to local cleanup.
        }
        records.remove(shareId: record.shareId)
    }
}
