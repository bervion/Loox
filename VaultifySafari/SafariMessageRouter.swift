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

    /// Face-ID-gated key release + a fresh on-disk shared store per message —
    /// the handler process is short-lived and never caches either. Same unlock
    /// path as the AutoFill extension (biometric-wrapped Vault Key from the
    /// shared keychain group; no Argon2 in this extension).
    private static var liveContext: WebExtensionRouterContext {
        WebExtensionRouterContext(
            retrieveKey: {
                try await BiometricKeyStore.retrieve(reason: appString("Unlock your vault"))
            },
            makeStore: {
                try VaultStore(recoverable: false)
            })
    }
}
