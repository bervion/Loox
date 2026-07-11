import Foundation

/// Ambient inputs shared by every rule in one audit run.
nonisolated struct AuditContext: Sendable {
    var now: Date = .now
    /// Whether network-backed rules (known-leak lookup) may run this audit.
    var onlineChecksEnabled: Bool = false
    /// Vault-key-derived HMAC key for secret-derived fingerprint markers
    /// (`AuditFingerprint.secretMarker`). Nil only in key-free contexts (tests).
    var secretMarkerKey: [UInt8]? = nil
}

/// One audit check. Rules are pure evaluators: snapshot in, findings out.
/// `requiresNetwork` splits the registry so an offline audit still completes
/// with every local rule and reports partial online coverage.
nonisolated protocol AuditRule: Sendable {
    var id: String { get }
    var version: Int { get }
    var category: AuditCategory { get }
    var requiresNetwork: Bool { get }
    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding]
}

nonisolated extension AuditRule {
    var requiresNetwork: Bool { false }
}

/// Central list of built-in local rules. Network rules live in the app target
/// (they need URLSession policy owned by the app) and are appended by the caller.
nonisolated enum AuditRuleRegistry {
    static func localRules() -> [any AuditRule] {
        [
            PasswordStrengthRule(),
            PasswordReuseRule(),
            TwoFactorRule(),
            PasskeyOpportunityRule(),
            ExactDuplicateRule(),
            ConflictingLoginRule(),
            InvalidTOTPRule(),
            IncompleteItemRule(),
            MissingMetadataRule(),
            URLHygieneRule(),
            StaleCredentialRule(),
        ]
    }
}
