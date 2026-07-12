//
//  SafariMessageRouter.swift
//  Pure request→response routing for the Safari web extension handler.
//  Kept free of SafariServices so the routing logic is unit-testable.
//
//  SECURITY INVARIANT: routes must never place vault contents or key
//  material into a response. Every payload crossing native→JS is
//  non-sensitive status data only.
//

import Foundation

nonisolated enum SafariMessageRouter {

    /// Longest echo payload we reflect back, to keep responses bounded.
    private static let maxEchoLength = 512

    /// Routes a raw `SFExtensionMessageKey` payload to a JSON-safe response
    /// dictionary. Unknown or malformed messages get a structured error so
    /// the JS layer can always distinguish "native unreachable" from
    /// "native rejected the message".
    static func route(_ message: Any?) -> [String: Any] {
        guard let cmd = command(of: message) else {
            return failure("malformedMessage")
        }

        switch cmd {
        case "echo", "ping":
            let payload = (message as? [String: Any])?["payload"] as? String ?? ""
            return [
                "ok": true,
                "cmd": cmd,
                "echo": String(payload.prefix(maxEchoLength)),
            ]
        default:
            return failure("unknownCommand")
        }
    }

    /// Extracts the `cmd` string from a raw message, if well-formed.
    static func command(of message: Any?) -> String? {
        (message as? [String: Any])?["cmd"] as? String
    }

    private static func failure(_ code: String) -> [String: Any] {
        ["ok": false, "error": code]
    }
}
