import Foundation

/// Outcome of one Quick View attempt, for device-local history only.
nonisolated enum QuickViewHistoryResult: String, Codable, Sendable {
    case completed
    case cancelled
    case failed
}

/// One minimal history row — `item_id + timestamp + result` ONLY (plan.md).
/// Deliberately excludes `session_id`, approved fields, the SAS phrase, and
/// the human code: a history row must never let a compromised device replay
/// or reconstruct a past session.
nonisolated struct QuickViewHistoryRow: Codable, Identifiable, Equatable, Sendable {
    var itemID: String
    var timestamp: Date
    var result: QuickViewHistoryResult

    var id: String { "\(itemID)-\(Int64(timestamp.timeIntervalSince1970 * 1000))" }
}

/// Keychain-backed, device-local registry of past Quick View attempts —
/// modeled on `LooxLinkRecordStore` (Keychain persistence pattern) but with a
/// deliberately narrower row shape (no revocable credential lives here, so
/// there is nothing to revoke — only a bounded history to cap and trim).
@MainActor @Observable final class QuickViewHistoryStore {
    private static let account = "quick-view-history"
    /// Bounded so an unattended device can't grow this file unboundedly.
    private static let maxRows = 200

    private(set) var rows: [QuickViewHistoryRow] = []

    init() {
        if let data = try? KeychainStore.get(account: Self.account),
           let decoded = try? JSONDecoder().decode([QuickViewHistoryRow].self, from: data) {
            rows = decoded
        }
    }

    func rows(forItem itemID: String) -> [QuickViewHistoryRow] {
        rows.filter { $0.itemID == itemID }.sorted { $0.timestamp > $1.timestamp }
    }

    func record(itemID: String, result: QuickViewHistoryResult, at timestamp: Date = .now) {
        rows.append(QuickViewHistoryRow(itemID: itemID, timestamp: timestamp, result: result))
        if rows.count > Self.maxRows {
            rows.sort { $0.timestamp < $1.timestamp }
            rows.removeFirst(rows.count - Self.maxRows)
        }
        persist()
    }

    func wipe() {
        rows = []
        KeychainStore.delete(account: Self.account)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rows) {
            try? KeychainStore.set(data, account: Self.account)
        }
    }
}
