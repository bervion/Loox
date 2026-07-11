import Foundation
import CryptoKit

// MARK: - Classification

/// How urgent a finding is. UI groups these into three buckets
/// (Act now = critical+high, Improve = medium, Maintain = low+info);
/// the raw severity stays available for detail views and accessibility.
nonisolated enum AuditSeverity: Int, Codable, Sendable, Comparable, CaseIterable {
    case info = 0, low, medium, high, critical

    static func < (lhs: AuditSeverity, rhs: AuditSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Which health pillar a finding belongs to. Mirrors the scoring pillars so a
/// finding always explains which part of the score it affects.
nonisolated enum AuditCategory: String, Codable, Sendable, CaseIterable {
    case exposure         // passwords found in known leaks
    case quality          // weak / guessable passwords
    case reuse            // password shared across items
    case authentication   // TOTP / passkey readiness
    case integrity        // duplicates, broken or incomplete data
    case maintenance      // staleness, missing metadata
}

/// Lifecycle of a finding across audits. `open` → `resolved` happens only when a
/// re-audit no longer produces the fingerprint; deleting the affected item yields
/// `noLongerMonitored` (never "fixed"). User-set states: `ignored`, `acceptedRisk`.
nonisolated enum FindingStatus: String, Codable, Sendable {
    case open, resolved, ignored, acceptedRisk, noLongerMonitored, needsRecheck
}

/// What kind of action fixes the finding — drives the remediation UI.
nonisolated enum RemediationType: String, Codable, Sendable {
    case changePassword, removeDuplicate, reviewItem, addTOTP, addPasskey, fixData
}

// MARK: - Finding

/// A single security/hygiene observation produced by one rule run.
/// Carries no plaintext secret: identity across runs is the `fingerprint`.
nonisolated struct AuditFinding: Identifiable, Sendable {
    /// Ephemeral UI identity for this run only; cross-run identity is `fingerprint`.
    let id = UUID()
    let ruleID: String
    let ruleVersion: Int
    let severity: AuditSeverity
    let category: AuditCategory
    /// Stable IDs of the vault items this finding is about (sorted).
    let affectedItemIDs: [String]
    /// Stable identity across audits — see `AuditFingerprint`.
    let fingerprint: String
    /// Localization key for the finding title ("finding.reuse.exact.title").
    let titleKey: String
    /// Pre-localized supporting detail ("Used by 4 items"), or nil.
    let detail: String?
    let remediation: RemediationType
    /// Static rule-based estimate used to sum an "estimated fix time".
    let estimatedFixSeconds: Int
    let detectedAt: Date
}

// MARK: - Fingerprint

/// Stable cross-run identity for findings. Never embeds plaintext: secret-derived
/// group markers must pass through `secretMarker` (one-way SHA-256) first.
nonisolated enum AuditFingerprint {
    static func make(ruleID: String, version: Int, itemIDs: [String], marker: String? = nil) -> String {
        var input = "\(ruleID)|\(version)|\(itemIDs.sorted().joined(separator: ","))"
        if let marker { input += "|\(marker)" }
        return hex(SHA256.hash(data: Data(input.utf8)))
    }

    /// One-way marker for a secret-derived group (e.g. a reuse group keyed by the
    /// shared password) so the fingerprint changes when the secret changes without
    /// the secret ever being stored.
    ///
    /// With a `key` (vault-key-derived, see `markerKey(fromVaultKey:)`) the marker
    /// is an HMAC: fingerprints sync as plaintext CloudKit record names, and an
    /// unkeyed hash would hand an offline password-verification oracle to anyone
    /// who can read the private database. The keyless fallback exists for
    /// key-free contexts (tests) only — production audits always pass a key.
    static func secretMarker(_ secret: String, key: [UInt8]? = nil) -> String {
        if let key {
            let mac = HMAC<SHA256>.authenticationCode(for: Data(secret.utf8),
                                                      using: SymmetricKey(data: key))
            return mac.map { String(format: "%02x", $0) }.joined()
        }
        return hex(SHA256.hash(data: Data(secret.utf8)))
    }

    /// Derives the fingerprint-marker key from the Vault Key (stable across the
    /// user's devices — every syncing device holds the Vault Key by definition).
    static func markerKey(fromVaultKey vaultKey: [UInt8]) -> [UInt8] {
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data("audit-finding-fingerprint-v1".utf8),
            using: SymmetricKey(data: vaultKey))
        return Array(mac)
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Static fix-time estimates (rule-based, no AI)

nonisolated enum AuditFixEstimate {
    static let changeLeakedPassword = 120
    static let replaceReusedPassword = 120
    static let enablePasskeyOrTOTP = 60
    static let removeDuplicate = 15
    static let reviewItem = 30
}
