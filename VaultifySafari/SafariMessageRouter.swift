//
//  SafariMessageRouter.swift
//  Appex-side binding of the shared `WebExtensionRouter`: supplies the LIVE
//  dependencies — per-operation Face ID key release and the shared App Group
//  store. All routing/validation logic lives in VaultifyCore
//  (`WebExtensionRouter` + `WebExtensionReader`) so `VaultifyTests` exercises
//  it with an injected key and an in-memory store.
//
//  SECURITY INVARIANT: responses never carry vault contents or key material
//  beyond what `WebExtensionReader` explicitly releases — match metadata for
//  the active origin, and a single whitelisted non-secret field value on an
//  explicit copy action.
//

import Foundation

nonisolated enum SafariMessageRouter {

    /// Routes a raw `SFExtensionMessageKey` payload to a JSON-safe response.
    static func respond(to message: Any?) async -> [String: Any] {
        await WebExtensionRouter.route(message, context: liveContext)
    }

    /// Extracts the `cmd` string from a raw message, for non-sensitive logging.
    static func command(of message: Any?) -> String? {
        (message as? [String: Any])?["cmd"] as? String
    }

    /// Key release + a fresh on-disk shared store per message — the handler
    /// process is short-lived and holds nothing in memory between messages.
    /// Unlock order: the short-lived native session (`ExtensionSessionStore`,
    /// no prompt, sliding window seeded by a prior unlock here or in the app)
    /// first, then the same Face-ID-gated path as the AutoFill extension
    /// (biometric-wrapped Vault Key from the shared keychain group; no Argon2
    /// in this extension). A fresh Face ID success re-seeds the session unless
    /// the mirrored auto-lock policy is "immediate".
    private static var liveContext: WebExtensionRouterContext {
        WebExtensionRouterContext(
            retrieveKey: {
                if let sessionKey = ExtensionSessionStore.retrieve() {
                    return sessionKey
                }
                let key = try await BiometricKeyStore.retrieve(
                    reason: appString("Unlock your vault"))
                ExtensionSessionStore.save(vaultKey: key,
                                           ttl: ExtensionSessionStore.configuredTTL())
                return key
            },
            makeStore: {
                try VaultStore(recoverable: false)
            })
    }
}
