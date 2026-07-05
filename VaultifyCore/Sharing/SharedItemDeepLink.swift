import Foundation

/// Codec for the `vaultify://shared-item/<id>` deep link. Used by the AutoFill
/// extension (which has no CloudKit entitlement, so it cannot run the
/// request/response ceremony itself) to hand a "Request code" tap back to the
/// containing app, which already has `ItemDetailScreen`'s Request control for
/// `askEachTime` TOTP capabilities.
nonisolated enum SharedItemDeepLink {
    private static let scheme = "vaultify"
    private static let host = "shared-item"

    /// Builds the URL for a projected shared item id (`SharedOrigin.itemID`).
    static func url(itemID: String) -> URL? {
        let encoded = itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemID
        return URL(string: "\(scheme)://\(host)/\(encoded)")
    }

    /// Recovers the item id from an opened URL, or nil if it isn't ours.
    static func itemID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        guard !path.isEmpty else { return nil }
        return path.removingPercentEncoding ?? path
    }
}
