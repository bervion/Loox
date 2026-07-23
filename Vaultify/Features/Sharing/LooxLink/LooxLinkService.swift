import Foundation

/// Orchestrates the Loox Link quick-share flow: build the plaintext envelope
/// from the owner's field selection → AES-256-GCM encrypt ON DEVICE → prove
/// app genuineness (App Attest, when the hardware supports it) → upload only
/// the ciphertext → mint the share URL with the content key in the fragment.
/// The server never sees a plaintext field or the key; revocation stores only
/// an opaque token.
@MainActor @Observable final class LooxLinkService {
    let records: LooxLinkRecordStore
    private let api: LooxLinkAPIClient
    /// Optional-capability state sink — independent from Private Email's
    /// (INV-CAP-03). Optional so tests without an AppEnvironment run unchanged.
    weak var capabilities: CapabilityStore?

    init(persistenceEnabled: Bool = true) {
        self.records = LooxLinkRecordStore(persistenceEnabled: persistenceEnabled)
        self.api = LooxLinkAPIClient()
    }

    struct CreatedLink {
        let url: URL
        let record: LooxLinkRecord
        /// Single-purpose shorten credential, alive exactly as long as this
        /// value (like the URL's fragment key): dismissing the sheet closes
        /// the shorten window for good. Never persisted anywhere.
        let shortenToken: String?
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

        // Breaker admission FIRST: with the worker already failing, the App
        // Attest round-trips below would keep hammering the same dead edge
        // before the guard ever ran.
        guard capabilities?.allowRequest(.shareLink) ?? true else {
            throw LooxLinkAPIError.capability(.active, retryAfter: nil)   // breaker open → "temporarily unavailable"
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
        let response: LooxLinkCreateResponse
        do {
            response = try await api.createShare(
                ciphertextB64: cipher.ciphertextB64, ivB64: cipher.ivB64,
                expiresInSeconds: expiry, oneTime: oneTime, assertion: assertion)
            capabilities?.noteSuccess(.shareLink)
        } catch LooxLinkAPIError.server(let status, let code)
                    where status == 409 && code == "entitlement_refresh_required" {
            // Lease died with an account state change (entitlement contract
            // §4): re-attach once, then ONE retry with a FRESH assertion (the
            // first challenge was consumed). Never a user-facing error unless
            // the refresh itself fails.
            guard await LooxEntitlementClientHooks.refreshHandler?() == true else {
                let failure = LooxLinkAPIError.server(status: 409, code: "entitlement_refresh_required")
                note(failure)
                throw failure
            }
            var retryAssertion: LooxLinkAPIClient.AssertionHeaders?
            if LooxLinkConfig.attestationEnabled, LooxLinkAttestation.isSupported {
                do {
                    retryAssertion = try await LooxLinkAttestation.assertCreateShare(
                        api: api, ciphertext: cipher.ciphertextRaw, iv: cipher.ivRaw,
                        expiresInSeconds: expiry, oneTime: oneTime)
                } catch {
                    if LooxLinkConfig.attestationRequired { throw error }
                }
            }
            do {
                response = try await api.createShare(
                    ciphertextB64: cipher.ciphertextB64, ivB64: cipher.ivB64,
                    expiresInSeconds: expiry, oneTime: oneTime, assertion: retryAssertion)
                capabilities?.noteSuccess(.shareLink)
            } catch {
                note(error)
                throw error
            }
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
        return CreatedLink(url: url, record: record, shortenToken: response.shortenToken)
    }

    /// Mint a short presentation link for a just-created share. Only callable
    /// while the create-success sheet still holds the fragment-bearing URL —
    /// afterwards the token and fragment are gone by design, and a new share
    /// is the only way to get a shareable link again. Returns the full short
    /// URL (fragment reattached in memory); the record keeps the fragment-free
    /// base only. Failure here never disturbs the created share.
    func shorten(_ created: CreatedLink) async throws -> URL {
        guard let token = created.shortenToken else { throw Failure.badServerData }
        guard capabilities?.allowRequest(.shortLink) ?? true else {
            throw LooxLinkAPIError.capability(.active, retryAfter: nil)   // breaker open
        }
        // App Attest binding for the shorten mutation — same shadow posture
        // as create-share until the server's independent ladder reaches
        // required (then failures block instead of falling through).
        var assertion: LooxLinkAPIClient.AssertionHeaders?
        if LooxLinkConfig.attestationEnabled, LooxLinkAttestation.isSupported {
            do {
                assertion = try await LooxLinkAttestation.assertShortenLink(
                    api: api, shareId: created.record.shareId, shortenToken: token)
            } catch {
                if LooxLinkConfig.shortenAssertionRequired { throw error }
                #if DEBUG
                print("[LooxLink] shorten attest failed (shadow mode, continuing): \(error)")
                #endif
            }
        }
        let response: LooxLinkShortenResponse
        do {
            response = try await api.createShortLink(shareId: created.record.shareId,
                                                     shortenToken: token, assertion: assertion)
            capabilities?.noteSuccess(.shortLink)
        } catch {
            note(error, for: .shortLink)
            throw error
        }
        guard let base = URL(string: response.shortURL),
              let full = LooxLinkConfig.composedShortURL(base: base, canonicalURL: created.url) else {
            throw Failure.badServerData
        }
        records.markShortened(shareId: created.record.shareId,
                              shortURLWithoutFragment: response.shortURL,
                              domainID: response.domainID)
        return full
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
    private func note(_ error: Error, for id: CapabilityID = .shareLink) {
        switch error {
        case LooxLinkAPIError.capability(let mode, let retryAfter):
            capabilities?.noteOperatorSignal(id, .init(mode: mode, retryAfter: retryAfter))
        case LooxLinkAPIError.server(let status, _) where (502...504).contains(status):
            capabilities?.noteInfrastructureFailure(id)
        case is URLError:
            capabilities?.noteInfrastructureFailure(id)
        default:
            capabilities?.noteServiceResponded(id)
        }
    }
}
