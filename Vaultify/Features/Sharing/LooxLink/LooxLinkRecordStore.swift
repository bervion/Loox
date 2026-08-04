import Foundation

/// One quick link this device created. The revoke token is the only
/// credential that can kill the link server-side, so records live in the
/// Keychain (device-local) — V1 revocation is available from the creating
/// device only (cross-device revoke is a pending backend decision).
/// The content key is deliberately NOT stored: once the sheet is dismissed,
/// only the recipient's URL can decrypt the snapshot.
nonisolated struct LooxLinkRecord: Codable, Identifiable, Equatable, Sendable {
    var shareId: String
    var revokeToken: String
    var itemId: String
    var createdAt: Date
    var expiresAt: Date
    /// Burn after read: the server deletes the share on its first view.
    var oneTime: Bool
    /// Presentation metadata for an optional short link, WITHOUT its fragment
    /// — the working link (fragment = key) exists only while the create sheet
    /// is up, so history can show "was shortened, on which host" but can never
    /// reconstruct a usable link. Deliberately not a `shortURL` field name a
    /// future reader might be tempted to copy-paste to a recipient.
    var shortURLWithoutFragment: String?
    var shortDomainID: String?

    var id: String { shareId }
    var isExpired: Bool { expiresAt <= .now }

    init(shareId: String, revokeToken: String, itemId: String,
         createdAt: Date, expiresAt: Date, oneTime: Bool = false,
         shortURLWithoutFragment: String? = nil, shortDomainID: String? = nil) {
        self.shareId = shareId
        self.revokeToken = revokeToken
        self.itemId = itemId
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.oneTime = oneTime
        self.shortURLWithoutFragment = shortURLWithoutFragment
        self.shortDomainID = shortDomainID
    }

    /// Custom decode so records persisted before `oneTime` existed still load
    /// (a missing key reads as false instead of dropping the whole registry).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shareId = try c.decode(String.self, forKey: .shareId)
        revokeToken = try c.decode(String.self, forKey: .revokeToken)
        itemId = try c.decode(String.self, forKey: .itemId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        expiresAt = try c.decode(Date.self, forKey: .expiresAt)
        oneTime = try c.decodeIfPresent(Bool.self, forKey: .oneTime) ?? false
        shortURLWithoutFragment = try c.decodeIfPresent(String.self, forKey: .shortURLWithoutFragment)
        shortDomainID = try c.decodeIfPresent(String.self, forKey: .shortDomainID)
    }
}

/// Keychain-backed registry of the device's active quick links.
@MainActor @Observable final class LooxLinkRecordStore {
    private static let account = "loox-link-records"
    @ObservationIgnored private let persistenceEnabled: Bool

    private(set) var records: [LooxLinkRecord] = []

    init(persistenceEnabled: Bool = true) {
        self.persistenceEnabled = persistenceEnabled
        if persistenceEnabled,
           let data = try? KeychainStore.get(account: Self.account),
           let decoded = try? JSONDecoder().decode([LooxLinkRecord].self, from: data) {
            // Expired links are dead server-side (404) — drop them on load.
            records = decoded.filter { !$0.isExpired }
        }
    }

    func records(forItem itemId: String) -> [LooxLinkRecord] {
        records.filter { $0.itemId == itemId && !$0.isExpired }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func add(_ record: LooxLinkRecord) {
        records.removeAll { $0.shareId == record.shareId }
        records.append(record)
        persist()
    }

    func remove(shareId: String) {
        records.removeAll { $0.shareId == shareId }
        persist()
    }

    /// Record that a share was shortened — fragment-free base only.
    func markShortened(shareId: String, shortURLWithoutFragment: String, domainID: String) {
        guard let index = records.firstIndex(where: { $0.shareId == shareId }) else { return }
        records[index].shortURLWithoutFragment = shortURLWithoutFragment
        records[index].shortDomainID = domainID
        persist()
    }

    /// Erase the registry, keeping only `retained` — the links an erase could
    /// not revoke. Their token is the single credential that can still kill
    /// them, so it outlives the vault instead of being destroyed with it.
    /// Retaining nothing deletes the Keychain entry outright.
    func wipe(keeping retained: [LooxLinkRecord] = []) {
        records = retained
        guard persistenceEnabled else { return }
        if retained.isEmpty {
            KeychainStore.delete(account: Self.account)
        } else {
            persist()
        }
    }

    private func persist() {
        guard persistenceEnabled else { return }
        if let data = try? JSONEncoder().encode(records) {
            try? KeychainStore.set(data, account: Self.account)
        }
    }
}
