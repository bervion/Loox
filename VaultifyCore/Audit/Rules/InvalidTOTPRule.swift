import Foundation

/// One-time-code fields whose stored secret cannot produce a code (bad base32,
/// malformed otpauth URI). These fail silently at sign-in time, so the audit
/// surfaces them before the user is locked out.
nonisolated struct InvalidTOTPRule: nonisolated AuditRule {
    let id = "integrity.otp-invalid"
    let version = 1
    let category = AuditCategory.integrity

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        snapshot.activeItems.compactMap { item in
            guard let secret = item.totpSecret, !secret.isEmpty,
                  TOTPGenerator.code(forStoredValue: secret, date: context.now) == nil
            else { return nil }
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                severity: .medium,
                category: category,
                affectedItemIDs: [item.id],
                fingerprint: AuditFingerprint.make(ruleID: id, version: version, itemIDs: [item.id]),
                titleKey: "finding.integrity.otp-invalid.title",
                detail: nil,
                remediation: .fixData,
                estimatedFixSeconds: AuditFixEstimate.enablePasskeyOrTOTP,
                detectedAt: context.now)
        }
    }
}
