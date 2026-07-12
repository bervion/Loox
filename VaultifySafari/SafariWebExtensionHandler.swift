//
//  SafariWebExtensionHandler.swift
//  Native side of the Safari web extension. Safari spawns this handler
//  per message (short-lived, headless process), delivers the JS payload via
//  `SFExtensionMessageKey`, and expects a single response item back — so all
//  handling is stateless request/response.
//
//  SECURITY INVARIANT: this handler never returns vault contents or key
//  material to the JS layer. Responses carry only non-sensitive status data.
//

import Foundation
import SafariServices
import os.log

nonisolated final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    private static let log = Logger(subsystem: "com.bervion.vaultify.safari", category: "handler")

    func beginRequest(with context: NSExtensionContext) {
        let message = (context.inputItems.first as? NSExtensionItem)?
            .userInfo?[SFExtensionMessageKey]

        let response = SafariMessageRouter.route(message)
        Self.log.debug("handled cmd=\(SafariMessageRouter.command(of: message) ?? "<none>", privacy: .public)")

        let item = NSExtensionItem()
        item.userInfo = [SFExtensionMessageKey: response]
        context.completeRequest(returningItems: [item], completionHandler: nil)
    }
}
