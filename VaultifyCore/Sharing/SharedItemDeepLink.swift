import Foundation

/// Codec for the `vaultify://shared-item/<id>` deep link. Hands a shared item
/// from the AutoFill extension back to the containing app, where
/// `ItemDetailScreen` has the full Request control for `askEachTime` TOTP.
///
/// This used to be the ONLY route, on the grounds that the extension had no
/// CloudKit entitlement — which was never true of the entitlements file, only
/// of the missing compile flag that made every CloudKit path there fail closed.
/// The extension now runs the request/response ceremony itself, so this link is
/// the deliberate ESCAPE HATCH rather than the default: following it ends the
/// AutoFill session (iOS offers no way to resume one), so it is offered only
/// when the user chooses it.
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
