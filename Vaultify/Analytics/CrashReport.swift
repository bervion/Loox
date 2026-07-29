import Foundation

/// One Crashlytics custom key: a snake_case name plus a small, non-identifying
/// value. Custom keys ride along with EVERY crash report, so this is the
/// strictest payload surface in the app.
///
/// PRIVACY CONTRACT (applies to every key added to the catalog): values may
/// carry app state, fixed identifiers we ship, coarse count buckets
/// (`AnalyticsBucket`), and setting states. They must NEVER carry vault
/// contents, item or Space names, usernames, emails, websites/domains, search
/// terms, file paths, or anything derived from them. `CrashReportPolicy`
/// enforces the shape mechanically — it cannot make the judgement call for you.
nonisolated struct CrashReportKey: Sendable {
    let name: String
    let value: CrashReportValue

    init(_ name: String, _ value: CrashReportValue) {
        self.name = name
        self.value = value
    }
}

/// The only value shapes a crash key can take. Numbers and booleans are
/// inherently non-identifying; strings are the risky case and are held to
/// `CrashReportPolicy.isSafeValueToken`.
nonisolated enum CrashReportValue: Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case bool(Bool)

    /// Bridged representation for `Crashlytics.setCustomValue(_:forKey:)`.
    var crashlyticsValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .bool(let value): return value
        }
    }

    var description: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        }
    }
}

/// The crash-payload gate, checked in DEBUG when a key is set and by
/// `CrashReportTests` over the whole catalog. Crashlytics has no server-side
/// validation and no privacy contract of its own — whatever we hand it is
/// uploaded and shown in the dashboard, so the rules have to hold here.
nonisolated enum CrashReportPolicy {
    static let keyNameLimit = 40
    static let stringValueLimit = 64
    /// Crashlytics keeps the most recent 64 custom keys per report; past that
    /// the earliest ones silently vanish from the payload.
    static let keyCountLimit = 64
    static let faultIdentifierLimit = 40

    /// A value token: lowercase letters, digits, underscore, dot, dash. The
    /// charset is the privacy guard, not cosmetics — it structurally excludes
    /// spaces, "/", "@" and ":", so a file path, URL, email address, item name
    /// or anything the user typed cannot pass as a value.
    static func isSafeValueToken(_ token: String) -> Bool {
        func isLower(_ scalar: Unicode.Scalar) -> Bool { (0x61...0x7A).contains(scalar.value) }
        func isDigit(_ scalar: Unicode.Scalar) -> Bool { (0x30...0x39).contains(scalar.value) }
        guard !token.isEmpty, token.count <= stringValueLimit else { return false }
        return token.unicodeScalars.allSatisfy {
            isLower($0) || isDigit($0) || $0 == "_" || $0 == "." || $0 == "-"
        }
    }

    /// Everything wrong with a key, as human-readable strings. Empty = valid.
    static func issues(in key: CrashReportKey) -> [String] {
        var issues: [String] = []
        if !AnalyticsPolicy.isValidIdentifier(key.name, limit: keyNameLimit) {
            issues.append("key name '\(key.name)' is not snake_case within \(keyNameLimit) chars")
        }
        if case .string(let token) = key.value, !isSafeValueToken(token) {
            issues.append("key '\(key.name)' carries a value that is not a safe token")
        }
        return issues
    }

    /// Everything wrong with a non-fatal category. Empty = valid.
    static func issues(in fault: CrashReportFault) -> [String] {
        var issues: [String] = []
        if !AnalyticsPolicy.isValidIdentifier(fault.identifier, limit: faultIdentifierLimit) {
            issues.append("fault identifier '\(fault.identifier)' is not snake_case within \(faultIdentifierLimit) chars")
        }
        if fault.rawValue <= 0 {
            issues.append("fault '\(fault.identifier)' has no stable grouping code")
        }
        let error = fault.error
        if error.domain != CrashReportFault.domain {
            issues.append("fault '\(fault.identifier)' escapes the fixed error domain")
        }
        // `record(error:)` uploads userInfo verbatim, so the dictionary must
        // hold nothing but the identifier we spelled ourselves.
        let unexpected = error.userInfo.filter { $0.key != NSLocalizedDescriptionKey }
        if !unexpected.isEmpty {
            issues.append("fault '\(fault.identifier)' carries extra userInfo keys: \(unexpected.keys.sorted())")
        }
        if error.userInfo[NSLocalizedDescriptionKey] as? String != fault.identifier {
            issues.append("fault '\(fault.identifier)' does not describe itself by its identifier")
        }
        return issues
    }
}
