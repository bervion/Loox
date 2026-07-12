import Foundation

/// Versioned native-messaging protocol between the Safari web extension's JS
/// layer and the native handler.
///
/// Request:  `{ v: 1, cmd: string, origin?: "https://host", itemId?: string,
///              fieldKind?: string, payload?: string }`
/// Response: `{ v: 1, ok: bool, error?: code, data?: {...} }`
///
/// SECURITY INVARIANT: the Vault Key and bulk vault contents never cross the
/// native→JS bridge. `listItems` returns match metadata only; `copyValue`
/// releases a single non-secret field value on an explicit user action and is
/// enforced natively (`WebExtensionReader.copyableKinds`) — never by the popup
/// hiding a button. The origin used for matching is supplied by the trusted
/// `browser.tabs` API in the background page, and is re-validated here as
/// https-with-host before any vault access.
nonisolated struct WebExtensionRequest: Sendable {
    static let supportedVersion = 1

    var version: Int
    var cmd: String
    var origin: String?
    var itemId: String?
    var fieldKind: String?
    var payload: String?

    /// Parses the raw `SFExtensionMessageKey` payload. Nil when the message is
    /// not a dictionary carrying a string `cmd` (structurally malformed).
    static func parse(_ raw: Any?) -> WebExtensionRequest? {
        guard let dictionary = raw as? [String: Any],
              let cmd = dictionary["cmd"] as? String else { return nil }
        return WebExtensionRequest(version: dictionary["v"] as? Int ?? 0,
                                   cmd: cmd,
                                   origin: dictionary["origin"] as? String,
                                   itemId: dictionary["itemId"] as? String,
                                   fieldKind: dictionary["fieldKind"] as? String,
                                   payload: dictionary["payload"] as? String)
    }
}

/// Dependencies injected by the appex (live Face ID + shared on-disk store) or
/// by unit tests (fixed key + in-memory store). The handler process is
/// per-message and short-lived, so every vault command re-retrieves the key —
/// nothing is cached between operations.
nonisolated struct WebExtensionRouterContext {
    /// Releases the Vault Key bytes (a Face ID prompt in the live context).
    var retrieveKey: @Sendable () async throws -> [UInt8]
    /// Opens the vault store. `@MainActor` because `VaultStore` requires it.
    var makeStore: @Sendable @MainActor () throws -> VaultStore
}

/// Pure request→response routing for the Safari web extension, kept free of
/// SafariServices (and of any prompting policy) so it is fully unit-testable.
nonisolated enum WebExtensionRouter {

    /// Longest echo payload reflected back, keeping responses bounded.
    private static let maxEchoLength = 512

    static func route(_ raw: Any?, context: WebExtensionRouterContext) async -> [String: Any] {
        guard let request = WebExtensionRequest.parse(raw) else {
            return failure("malformedMessage")
        }
        guard request.version == WebExtensionRequest.supportedVersion else {
            return failure("unsupportedVersion")
        }
        switch request.cmd {
        case "echo", "ping":
            // Connectivity diagnostic retained from the extension skeleton.
            return success(["echo": String((request.payload ?? "").prefix(maxEchoLength))])
        case "status":
            // Always locked: the handler never holds the key between messages,
            // so unlock state only exists for the duration of one operation.
            return success(["locked": true])
        case "listItems":
            return await listItems(request, context: context)
        case "copyValue":
            return await copyValue(request, context: context)
        default:
            return failure("unknownCommand")
        }
    }

    // MARK: - Vault commands (per-operation key retrieval)

    private static func listItems(_ request: WebExtensionRequest,
                                  context: WebExtensionRouterContext) async -> [String: Any] {
        guard let host = httpsHost(fromOrigin: request.origin) else {
            return failure("invalidOrigin")
        }
        let key: SecureBytes
        do { key = try await unlockedKey(context) } catch { return unlockFailure(error) }
        do {
            let lists = try await MainActor.run { () -> WebExtensionReader.ItemLists in
                let store = try context.makeStore()
                return WebExtensionReader.itemsMatching(host: host, store: store, key: key)
            }
            return success(listsData(lists))
        } catch {
            return failure("storeUnavailable")
        }
    }

    private static func copyValue(_ request: WebExtensionRequest,
                                  context: WebExtensionRouterContext) async -> [String: Any] {
        guard let itemId = request.itemId, !itemId.isEmpty,
              let rawKind = request.fieldKind, !rawKind.isEmpty else {
            return failure("malformedMessage")
        }
        // Whitelist gate BEFORE any unlock: a secret kind never triggers Face ID.
        guard let kind = FieldKind(rawValue: rawKind),
              WebExtensionReader.copyableKinds.contains(kind) else {
            return failure("forbidden")
        }
        let key: SecureBytes
        do { key = try await unlockedKey(context) } catch { return unlockFailure(error) }
        do {
            let value = try await MainActor.run { () -> String in
                let store = try context.makeStore()
                return try WebExtensionReader.copyableValue(itemId: itemId, kind: kind,
                                                            store: store, key: key)
            }
            return success(["value": value])
        } catch let error as WebExtensionReader.ReadError {
            switch error {
            case .itemNotFound: return failure("itemNotFound")
            case .forbidden: return failure("forbidden")
            }
        } catch {
            return failure("storeUnavailable")
        }
    }

    // MARK: - Helpers

    /// Wraps the retrieved key into locked, zero-on-release storage and scrubs
    /// the transient array so raw key bytes cannot linger in swap or a heap dump.
    private static func unlockedKey(_ context: WebExtensionRouterContext) async throws -> SecureBytes {
        var raw = try await context.retrieveKey()
        defer { secureZero(&raw) }
        return SecureBytes(raw)
    }

    private static func unlockFailure(_ error: Error) -> [String: Any] {
        if case BiometricKeyStore.Failure.cancelled = error {
            return failure("unlockCancelled")
        }
        return failure("unlockFailed")
    }

    /// Lowercased host of a well-formed https origin; nil for anything else
    /// (http, custom schemes, reader-mode/about: pages, garbage input).
    static func httpsHost(fromOrigin origin: String?) -> String? {
        guard let origin,
              let url = URL(string: origin),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty else { return nil }
        return host
    }

    private static func listsData(_ lists: WebExtensionReader.ItemLists) -> [String: Any] {
        let logins: [[String: Any]] = lists.logins.map { login in
            ["id": login.id, "title": login.title, "username": login.username]
        }
        let identities: [[String: Any]] = lists.identities.map { identity in
            ["id": identity.id, "title": identity.title]
        }
        let cards: [[String: Any]] = lists.cards.map { card in
            ["id": card.id, "title": card.title, "brand": card.brand, "last4": card.last4]
        }
        return ["logins": logins, "identities": identities, "cards": cards]
    }

    private static func success(_ data: [String: Any]) -> [String: Any] {
        ["v": WebExtensionRequest.supportedVersion, "ok": true, "data": data]
    }

    private static func failure(_ code: String) -> [String: Any] {
        ["v": WebExtensionRequest.supportedVersion, "ok": false, "error": code]
    }
}
