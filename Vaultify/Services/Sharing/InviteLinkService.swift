import CloudKit
import CryptoKit
import Foundation

/// Pretty invite links over the CloudKit PUBLIC database:
///
///     https://invite.looxpassword.com/i/<token>#k=<key>
///
/// The token locates a public-DB record whose payload is AES-GCM ciphertext;
/// the symmetric key travels ONLY in the URL fragment (never sent to any
/// server — fragments don't leave the client, and Universal Links hand the
/// full URL to the app). The public database therefore sees: an opaque
/// record name, ciphertext, and an expiry — never the CKShare URL, never
/// PII. Anyone with the LINK can resolve the CKShare URL, but acceptance is
/// still bound to the looked-up participant's iCloud account (the URL is
/// routing, not a bearer capability).
///
/// This is the FALLBACK tier (recipient may not be a Loox user yet). The
/// Loox-to-Loox auto-inbox tier (envelope sealed to B's key) layers on the
/// same record type later.
@MainActor final class InviteLinkService {
    enum Failure: Error, LocalizedError {
        case malformedLink
        case notFoundOrExpired
        case shareUnavailable

        var errorDescription: String? {
            switch self {
            case .malformedLink: return appString("This invite link isn't valid.")
            case .notFoundOrExpired: return appString("This invitation has expired or was withdrawn.")
            case .shareUnavailable: return appString("The owner stopped sharing this item.")
            }
        }
    }

    static let host = "invite.looxpassword.com"
    private static let recordType = "LooxInvite"
    private static let blobField = "blob"
    private static let expiresField = "expiresAtMs"
    /// Invites are bootstrap artifacts, not grants (user-locked: 24h–7d).
    private static let lifetimeMs: Int64 = 7 * 24 * 3600 * 1000

    private lazy var container = CKContainer(identifier: ApprovalConfig.containerID)
    private var publicDatabase: CKDatabase { container.publicCloudDatabase }

    private struct InvitePayload: Codable {
        var shareURL: String
        var createdAtUnixMs: Int64
    }

    // MARK: Owner side — mint a link for a created CKShare

    func createInviteLink(shareURL: URL) async throws -> URL {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let key = CryptoRandom.bytes(32)
        let payload = InvitePayload(shareURL: shareURL.absoluteString, createdAtUnixMs: nowMs)
        let ciphertext = try AESGCM.seal(JSONEncoder().encode(payload), key: key)

        let token = ApprovalConfig.opaqueName()
        let record = CKRecord(recordType: Self.recordType,
                              recordID: CKRecord.ID(recordName: "inv-" + token))
        record[Self.blobField] = ciphertext as CKRecordValue
        record[Self.expiresField] = (nowMs + Self.lifetimeMs) as CKRecordValue
        let saved = try await publicDatabase.modifyRecords(saving: [record], deleting: [])
        for (_, result) in saved.saveResults { _ = try result.get() }

        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.path = "/i/\(token)"
        components.fragment = "k=" + Data(key).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard let url = components.url else { throw Failure.malformedLink }
        return url
    }

    // MARK: Recipient side — universal link → CKShare metadata → accept

    /// True when this URL is one of ours (used by the scene routing).
    nonisolated static func isInviteLink(_ url: URL) -> Bool {
        url.host == host && url.path.hasPrefix("/i/")
    }

    /// Resolve and accept: token → public record → decrypt with the fragment
    /// key → REAL CKShare URL → fetch share metadata → accept. Never
    /// fabricates metadata — the CloudKit acceptance contract stays intact.
    func acceptInvite(from url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              Self.isInviteLink(url) else { throw Failure.malformedLink }
        let token = url.lastPathComponent
        guard token.count >= 32,
              let fragment = components.fragment, fragment.hasPrefix("k="),
              let key = Data(base64URLTolerant: String(fragment.dropFirst(2))),
              key.count == 32 else { throw Failure.malformedLink }

        let record: CKRecord
        do {
            record = try await publicDatabase.record(
                for: CKRecord.ID(recordName: "inv-" + token))
        } catch let error as CKError where error.code == .unknownItem {
            throw Failure.notFoundOrExpired
        }
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        guard let blob = record[Self.blobField] as? Data,
              let expiresAt = record[Self.expiresField] as? Int64, nowMs < expiresAt,
              let payload = try? JSONDecoder().decode(InvitePayload.self,
                                                      from: AESGCM.open(blob, key: Array(key))),
              let shareURL = URL(string: payload.shareURL) else {
            throw Failure.notFoundOrExpired
        }

        // CloudKit acceptance contract: URL → CKShare.Metadata → accept.
        let metadata = try await fetchShareMetadata(shareURL: shareURL)
        do {
            _ = try await container.accept(metadata)
        } catch let error as CKError where error.code == .alreadyShared {
            // Accepting twice is fine — treat as success.
        }
        // Same downstream as a native share accept (breadcrumb + resume).
        UserDefaults.standard.set(true, forKey: SharedConfig.pendingShareAcceptanceKey)
        NotificationCenter.default.post(name: .vaultShareAccepted, object: nil)
    }

    private func fetchShareMetadata(shareURL: URL) async throws -> CKShare.Metadata {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchShareMetadataOperation(shareURLs: [shareURL])
            var fetched: CKShare.Metadata?
            operation.perShareMetadataResultBlock = { _, result in
                if case .success(let metadata) = result { fetched = metadata }
            }
            operation.fetchShareMetadataResultBlock = { result in
                switch result {
                case .success:
                    if let fetched {
                        continuation.resume(returning: fetched)
                    } else {
                        continuation.resume(throwing: Failure.shareUnavailable)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }
}

private extension Data {
    init?(base64URLTolerant string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}
