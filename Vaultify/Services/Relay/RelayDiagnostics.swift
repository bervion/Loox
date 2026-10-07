import Foundation
import os

/// Technical relay breadcrumbs. Callers supply fixed `key=value` metadata, never
/// user input, identifiers, request bodies or cryptographic material. Unknown
/// fields and unsafe values are discarded before reaching either output.
///
/// Debug keeps a bounded local file for on-device inspection. Release mirrors
/// sanitized metadata only to Logger and never reads or writes the file.
nonisolated enum RelayDiagnostics {
    private static let logger = Logger(subsystem: "com.bervion.vaultify", category: "relay-diagnostics")
    private static let lock = NSLock()
    private static let maximumLines = 600
    private static let maximumFields = 24
    private static let maximumValueLength = 80
    private static let allowedFields: Set<String> = [
        "stage", "phase", "operation", "kind", "attempt", "epoch", "commandVersion",
        "genesisKey", "supported", "environment", "host", "cached", "registered",
        "http", "status", "code", "backendCode", "reason", "errorDomain", "domain",
        "failure", "recovered"
    ]

    #if DEBUG
    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "relay-diagnostics.log")
    }
    #endif

    static func record(_ message: String) {
        let metadata = sanitizedMessage(message)
        guard !metadata.isEmpty else { return }
        logger.info("\(metadata, privacy: .public)")
        #if DEBUG
        let line = "\(Date().ISO8601Format()) \(metadata)"
        lock.lock()
        defer { lock.unlock() }
        var lines = (try? String(contentsOf: fileURL, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? []
        lines.append(line)
        if lines.count > maximumLines { lines.removeFirst(lines.count - maximumLines) }
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
        #endif
    }

    static func contents() -> String {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        #else
        return ""
        #endif
    }

    static func clear() {
        #if DEBUG
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
        #endif
    }

    /// Only short ASCII metadata tokens survive. Field names exclude identifiers
    /// and payloads; value syntax rejects email addresses, URLs and JSON.
    static func sanitizedMessage(_ message: String) -> String {
        message.split(whereSeparator: { $0.isWhitespace }).prefix(maximumFields).compactMap { field in
            let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, allowedFields.contains(String(parts[0])),
                  !parts[1].isEmpty, parts[1].count <= maximumValueLength,
                  parts[1].utf8.allSatisfy({ byte in
                      (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                          || byte == 45 || byte == 46 || byte == 95
                  }) else { return nil }
            return String(field)
        }.joined(separator: " ")
    }
}
