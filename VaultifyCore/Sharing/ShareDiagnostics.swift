import Foundation
import os

/// On-device diagnostics for the Approval-Mode share handshake.
///
/// Console capture is unreliable on real devices, and the share bug spans two
/// phones (owner + recipient) that can't both be run from Xcode at once — so
/// every step appends a timestamped line to a file in the shared App Group
/// container (`share-diagnostics.log`) that a debug screen renders and can copy
/// out. Lines are also mirrored to `os.Logger` (filter Console.app on `###`).
///
/// DEBUG-only: in Release the file write compiles out to a no-op, so nothing is
/// persisted in TestFlight/App Store builds.
nonisolated enum ShareDiagnostics {
    private static let logger = Logger(subsystem: "com.bervion.vaultify", category: "share")
    private static let lock = NSLock()
    private static let maxLines = 600

    private static var fileURL: URL {
        SharedConfig.containerURL.appending(path: "share-diagnostics.log")
    }

    /// Append a diagnostic line. `tag` groups the step (ACCEPT / RESUME / ZONES
    /// / OWNER …); `role` marks which device wrote it if known.
    static func log(_ tag: String, _ message: String) {
        #if DEBUG
        let line = "### [\(timestamp())] \(tag): \(message)"
        logger.debug("\(line, privacy: .public)")
        lock.lock()
        defer { lock.unlock() }
        var lines = (try? String(contentsOf: fileURL, encoding: .utf8))?
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init) ?? []
        lines.append(line)
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        #endif
    }

    /// Current log contents (newest last), for the debug viewer.
    static func contents() -> String {
        lock.lock()
        defer { lock.unlock() }
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func timestamp() -> String {
        let now = Date()
        let c = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        return String(format: "%02d:%02d:%02d.%03d",
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0, (c.nanosecond ?? 0) / 1_000_000)
    }
}
