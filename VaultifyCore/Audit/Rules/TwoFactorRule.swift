import Foundation

/// Flags logins on services known to support 2FA where no verification code is
/// saved in the vault. Wording contract: this means "no code saved HERE", never
/// "2FA is off" — the user may keep 2FA elsewhere (proposal Module E).
nonisolated struct TwoFactorRule: nonisolated AuditRule {
    let id = "auth.totp-missing"
    let version = 1
    let category = AuditCategory.authentication

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        snapshot.activeItems.compactMap { item in
            guard item.loginHygieneEligible, !item.hasTOTP,
                  TwoFactorCatalog.supports2FA(urls: item.rawURLs, title: item.title)
            else { return nil }
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                severity: .low,
                category: category,
                affectedItemIDs: [item.id],
                // Catalog version rides the fingerprint so dataset updates
                // re-surface the finding for review (see PasskeyOpportunityRule).
                fingerprint: AuditFingerprint.make(
                    ruleID: id, version: version, itemIDs: [item.id],
                    marker: ServiceCapabilityCatalog.fingerprintMarker),
                titleKey: "finding.auth.totp-missing.title",
                detail: nil,
                remediation: .addTOTP,
                estimatedFixSeconds: AuditFixEstimate.enablePasskeyOrTOTP,
                detectedAt: context.now)
        }
    }
}
