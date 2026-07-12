//
//  SafariWebExtensionHandler.swift
//  Native side of the Safari web extension. Safari spawns this handler
//  per message (short-lived, headless process), delivers the JS payload via
//  `SFExtensionMessageKey`, and expects a single response item back — so all
//  handling is stateless request/response. Vault commands retrieve the
//  biometric-wrapped Vault Key per operation and drop it before responding.
//
//  SECURITY INVARIANT: this handler never returns bulk vault contents or key
//  material to the JS layer — only origin-scoped match metadata and, on an
//  explicit copy action, a single whitelisted non-secret field value.
//

import Foundation
import SafariServices
import os.log

nonisolated final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    private static let log = Logger(subsystem: "com.bervion.vaultify.safari", category: "handler")

    func beginRequest(with context: NSExtensionContext) {
        let message = (context.inputItems.first as? NSExtensionItem)?
            .userInfo?[SFExtensionMessageKey]
        Self.log.debug("routing cmd=\(SafariMessageRouter.command(of: message) ?? "<none>", privacy: .public)")

        // Vault commands are async (Face ID + store read); the extension
        // context stays open until completeRequest fires from the task.
        Task { @MainActor in
            let response = await SafariMessageRouter.respond(to: message)
            let item = NSExtensionItem()
            item.userInfo = [SFExtensionMessageKey: response]
            context.completeRequest(returningItems: [item], completionHandler: nil)
        }
    }
}
