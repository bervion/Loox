import Foundation

/// Versioned native-messaging protocol between the Safari web extension's JS
/// layer and the native handler.
///
/// Request:  `{ v: 1, cmd: string, origin?: "https://host", itemId?: string,
///              fieldKind?: string, category?: string, payload?: string,
///              username?: string, password?: string, title?: string,
///              length?: int }`
/// Response: `{ v: 1, ok: bool, error?: code, data?: {...} }`
///
/// SECURITY INVARIANT: the Vault Key and bulk vault contents never cross the
/// native→JS bridge. `listItems` returns match metadata only; `copyValue`
/// releases a single non-secret field value on an explicit user action and is
/// enforced natively (`WebExtensionReader.copyableKinds`) — never by the popup
/// hiding a button. `getFillPayload` is the ONLY command returning vault
/// values for page injection: single item, identity/card categories only,
/// issued by the background page solely inside its popup-initiated fill flow.
/// `generatePassword` returns a freshly generated value (never vault data).
/// `saveLogin` moves a password in the OPPOSITE direction (JS→native) and only
/// on the user's explicit Save tap in the in-page overlay. The origin used for
/// matching is supplied by the trusted `browser.tabs` API in the background
/// page, and is re-validated here as https-with-host before any vault access.
nonisolated struct WebExtensionRequest: Sendable {
    static let supportedVersion = 1

    var version: Int
    var cmd: String
    var origin: String?
    var itemId: String?
    var fieldKind: String?
    var category: String?
    var payload: String?
    var username: String?
    var password: String?
    var title: String?
    var length: Int?

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
                                   category: dictionary["category"] as? String,
                                   payload: dictionary["payload"] as? String,
                                   username: dictionary["username"] as? String,
                                   password: dictionary["password"] as? String,
                                   title: dictionary["title"] as? String,
                                   length: dictionary["length"] as? Int)
    }
}

/// Dependencies injected by the appex (session-or-Face-ID key release + shared
/// on-disk store) or by unit tests (fixed key + in-memory store). The handler
/// process is per-message and short-lived, so every vault command re-retrieves
/// the key — nothing is cached in memory between operations (the appex context
/// may satisfy the retrieval from a short-lived native keychain session).
nonisolated struct WebExtensionRouterContext {
    /// Releases the Vault Key bytes (a Face ID prompt in the live context).
    var retrieveKey: @Sendable () async throws -> [UInt8]
    /// Opens the vault store. `@MainActor` because `VaultStore` requires it.
    var makeStore: @Sendable @MainActor () throws -> VaultStore
    /// True when the OS-native save-password sheet owns the save UX for our
    /// credential provider (iOS 26.2+). The extension then suppresses its own
    /// in-page save overlay so one signup never produces two save prompts.
    var nativeSaveActive: @Sendable () -> Bool = {
        WebExtensionSaveGate.nativeSavePathActive()
    }
    /// Non-secret shared defaults carrying the never-save host list and the
    /// generate rate-limit window. Injected so tests use a scratch suite.
    var configDefaults: @Sendable () -> UserDefaults = {
        SharedConfig.sharedDefaults
    }
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
            // Conservatively "locked": the popup auto-attempts the unlock+list
            // flow instead of querying lock state, so this diagnostic reply
            // never needs to reflect the native session. Capabilities let the
            // JS layer learn (only natively knowable) platform facts.
            let capabilities = ["nativeSave": context.nativeSaveActive()]
            return success(["locked": true, "capabilities": capabilities])
        case "listItems":
            return await listItems(request, context: context)
        case "copyValue":
            return await copyValue(request, context: context)
        case "getFillPayload":
            return await getFillPayload(request, context: context)
        case "generatePassword":
            return generatePassword(request, context: context)
        case "saveGate":
            return saveGate(request, context: context)
        case "neverSave":
            return neverSave(request, context: context)
        case "saveLogin":
            return await saveLogin(request, context: context)
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

    /// The single value-returning command for page injection. Requirements
    /// checked BEFORE any unlock so a bad request never triggers Face ID:
    /// well-formed https origin (the background page pins the payload to the
    /// tab it derived this origin from), non-empty item id, and one of the two
    /// fillable categories. Passwords are structurally unreachable here —
    /// `fillPayload` serves identity/card items only and drops secret kinds.
    private static func getFillPayload(_ request: WebExtensionRequest,
                                       context: WebExtensionRouterContext) async -> [String: Any] {
        guard httpsHost(fromOrigin: request.origin) != nil else {
            return failure("invalidOrigin")
        }
        guard let itemId = request.itemId, !itemId.isEmpty,
              let rawCategory = request.category,
              let category = ItemCategory(rawValue: rawCategory) else {
            return failure("malformedMessage")
        }
        guard WebExtensionReader.fillableCategories.contains(category) else {
            return failure("forbidden")
        }
        let key: SecureBytes
        do { key = try await unlockedKey(context) } catch { return unlockFailure(error) }
        do {
            let values = try await MainActor.run { () -> [String: String] in
                let store = try context.makeStore()
                return try WebExtensionReader.fillPayload(itemId: itemId, category: category,
                                                          store: store, key: key)
            }
            // Freshness hint: the background page must discard an undelivered
            // payload after this moment (it also enforces its own 10s cap).
            let expiresAt = Int((Date.now.timeIntervalSince1970 + 10) * 1000)
            return success(["values": values,
                            "category": category.rawValue,
                            "expiresAt": expiresAt])
        } catch let error as WebExtensionReader.ReadError {
            switch error {
            case .itemNotFound: return failure("itemNotFound")
            case .forbidden: return failure("forbidden")
            }
        } catch {
            return failure("storeUnavailable")
        }
    }

    // MARK: - Signup assist (generate + save)

    private enum SaveLoginError: Error { case duplicate }

    /// Password length bounds accepted from the JS layer.
    private static let generateLengthRange = 8...64
    /// Longest password accepted for a save (matches the app's editor limits
    /// generously; anything longer is a malformed or hostile request).
    private static let maxSavedSecretLength = 512
    private static let maxSavedTitleLength = 120

    /// A freshly generated password for the popup's signup-assist action.
    /// Never vault data, so no unlock is required — but rate-limited as
    /// defense in depth against a compromised renderer scripting the
    /// extension messaging surface.
    private static func generatePassword(_ request: WebExtensionRequest,
                                         context: WebExtensionRouterContext) -> [String: Any] {
        var options = PasswordOptions()
        if let length = request.length {
            guard generateLengthRange.contains(length) else {
                return failure("malformedMessage")
            }
            options.length = length
        }
        guard WebExtensionSaveGate.allowGenerate(defaults: context.configDefaults()) else {
            return failure("rateLimited")
        }
        return success(["password": PasswordGenerator.generate(options)])
    }

    /// Whether the content script may offer its in-page save overlay for this
    /// origin: well-formed https, no OS-native save sheet on this device, and
    /// the host not on the user's never-save list. Metadata only — no unlock.
    private static func saveGate(_ request: WebExtensionRequest,
                                 context: WebExtensionRouterContext) -> [String: Any] {
        guard let host = httpsHost(fromOrigin: request.origin) else {
            return failure("invalidOrigin")
        }
        let neverSaved = WebExtensionSaveGate.isNeverSaved(host: host,
                                                           defaults: context.configDefaults())
        let offer = !context.nativeSaveActive() && !neverSaved
        return success(["offer": offer])
    }

    /// "Never for this site": stores the bare host (never a secret) in shared
    /// defaults so the opt-out survives extension reinstalls.
    private static func neverSave(_ request: WebExtensionRequest,
                                  context: WebExtensionRouterContext) -> [String: Any] {
        guard let host = httpsHost(fromOrigin: request.origin) else {
            return failure("invalidOrigin")
        }
        WebExtensionSaveGate.addNeverSave(host: host, defaults: context.configDefaults())
        return success(["stored": true])
    }

    /// Writes a brand-new login captured at signup-submit intent. The password
    /// crosses JS→native ONLY here, and only because the user tapped Save in
    /// the overlay; Face ID (or the short-lived native session) gates the
    /// write like every other vault operation. All shape checks, the
    /// save-gate belt, and a per-host rate limit run BEFORE any unlock so a
    /// forged or out-of-band request never triggers Face ID, cannot spam
    /// vault writes inside a warm session, and cannot use the duplicate
    /// error as a high-rate username-existence probe. A same-host
    /// same-username login already in the vault yields `duplicate` instead
    /// of a second copy.
    private static func saveLogin(_ request: WebExtensionRequest,
                                  context: WebExtensionRouterContext) async -> [String: Any] {
        guard let origin = request.origin,
              let host = httpsHost(fromOrigin: origin) else {
            return failure("invalidOrigin")
        }
        guard let password = request.password, !password.isEmpty,
              password.count <= maxSavedSecretLength,
              let username = request.username,
              username.count <= maxSavedSecretLength else {
            return failure("malformedMessage")
        }
        let rawTitle = request.title ?? ""
        guard rawTitle.count <= maxSavedTitleLength else {
            return failure("malformedMessage")
        }
        // Belt: the overlay is suppressed when the native save sheet owns the
        // flow or the user opted this host out — a saveLogin arriving anyway
        // is out of band and refused before any unlock.
        let neverSaved = WebExtensionSaveGate.isNeverSaved(host: host,
                                                           defaults: context.configDefaults())
        guard !context.nativeSaveActive(), !neverSaved else {
            return failure("forbidden")
        }
        guard WebExtensionSaveGate.allowSave(host: host,
                                             defaults: context.configDefaults()) else {
            return failure("rateLimited")
        }
        let key: SecureBytes
        do { key = try await unlockedKey(context) } catch { return unlockFailure(error) }
        do {
            let itemId = try await MainActor.run { () -> String in
                let store = try context.makeStore()
                let lists = WebExtensionReader.itemsMatching(host: host, store: store, key: key)
                // Trim before comparing: `createLogin` stores the trimmed
                // username, so an untrimmed compare would let " alice" slip
                // past the gate and land as a true duplicate of "alice".
                let wanted = username.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let exists = lists.logins.contains { $0.username.lowercased() == wanted }
                if exists { throw SaveLoginError.duplicate }
                return try VaultWriter.createLogin(store: store, site: origin,
                                                   username: username, password: password,
                                                   title: rawTitle, vaultKey: key)
            }
            return success(["itemId": itemId])
        } catch is SaveLoginError {
            return failure("duplicate")
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
