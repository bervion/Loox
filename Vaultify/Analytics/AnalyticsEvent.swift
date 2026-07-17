import Foundation

/// One analytics event: a GA4-safe snake_case name plus a small, non-identifying
/// parameter set.
///
/// PRIVACY CONTRACT (applies to every event added to the catalog): parameters may
/// carry item TYPES, coarse count buckets (`AnalyticsBucket`), our own product IDs,
/// and setting states. They must NEVER carry vault contents, item or Space names,
/// usernames, emails, websites/domains, search terms, file names, or anything
/// derived from them. When in doubt, bucket it or drop it.
nonisolated struct AnalyticsEvent: Sendable {
    let name: String
    let parameters: [String: AnalyticsValue]

    init(_ name: String, _ parameters: [String: AnalyticsValue] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

/// The only value shapes an event parameter can take — mirrors what GA4 accepts
/// (strings and numbers; booleans travel as 0/1).
nonisolated enum AnalyticsValue: Sendable, CustomStringConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    /// Bridged representation for the Firebase `logEvent(_:parameters:)` API.
    var firebaseValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value ? 1 : 0
        }
    }

    var description: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        }
    }
}

extension AnalyticsValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                          ExpressibleByBooleanLiteral {
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }
}

/// Coarse magnitudes for anything countable. Raw counts of a user's credentials or
/// findings are more fingerprint than product signal — buckets answer the product
/// question ("do people with many findings convert?") without profiling the vault.
nonisolated enum AnalyticsBucket {
    static func count(_ n: Int) -> String {
        switch n {
        case ..<1: return "0"
        case 1...5: return "1_5"
        case 6...20: return "6_20"
        case 21...50: return "21_50"
        default: return "over_50"
        }
    }
}

/// GA4 hard limits and taxonomy rules, checked in DEBUG at log time and by
/// `AnalyticsEventTests` over the whole catalog — a silently dropped event
/// (GA4 discards violations server-side) is worse than a build-time failure.
nonisolated enum AnalyticsPolicy {
    static let eventNameLimit = 40
    static let parameterCountLimit = 25
    static let parameterKeyLimit = 40
    static let parameterStringValueLimit = 100
    static let userPropertyNameLimit = 24
    static let userPropertyValueLimit = 36
    /// Reserved by Google — events/properties with these prefixes are rejected.
    static let reservedPrefixes = ["firebase_", "google_", "ga_"]

    /// snake_case identifier: starts with a lowercase letter, then lowercase
    /// letters, digits, or underscores. Keeps the taxonomy grep-able and inside
    /// GA4's accepted charset.
    static func isValidIdentifier(_ identifier: String, limit: Int) -> Bool {
        func isLower(_ scalar: Unicode.Scalar) -> Bool { (0x61...0x7A).contains(scalar.value) }
        func isDigit(_ scalar: Unicode.Scalar) -> Bool { (0x30...0x39).contains(scalar.value) }
        let scalars = identifier.unicodeScalars
        guard !identifier.isEmpty, identifier.count <= limit,
              let first = scalars.first, isLower(first) else { return false }
        return scalars.allSatisfy { isLower($0) || isDigit($0) || $0 == "_" }
    }

    /// Everything wrong with an event, as human-readable strings. Empty = valid.
    static func issues(in event: AnalyticsEvent) -> [String] {
        var issues: [String] = []
        if !isValidIdentifier(event.name, limit: eventNameLimit) {
            issues.append("event name '\(event.name)' is not snake_case within \(eventNameLimit) chars")
        }
        if reservedPrefixes.contains(where: event.name.hasPrefix) {
            issues.append("event name '\(event.name)' uses a reserved prefix")
        }
        if event.parameters.count > parameterCountLimit {
            issues.append("event '\(event.name)' has \(event.parameters.count) parameters (max \(parameterCountLimit))")
        }
        for (key, value) in event.parameters {
            if !isValidIdentifier(key, limit: parameterKeyLimit) {
                issues.append("parameter key '\(key)' is not snake_case within \(parameterKeyLimit) chars")
            }
            if reservedPrefixes.contains(where: key.hasPrefix) {
                issues.append("parameter key '\(key)' uses a reserved prefix")
            }
            if case .string(let string) = value, string.count > parameterStringValueLimit {
                issues.append("parameter '\(key)' value exceeds \(parameterStringValueLimit) chars")
            }
        }
        return issues
    }
}
