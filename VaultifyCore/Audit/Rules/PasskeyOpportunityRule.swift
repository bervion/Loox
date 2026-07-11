import Foundation

/// Sites known (curated catalog) to support passkeys where this vault has no
/// passkey saved. Wording contract: "Loox does not currently have a passkey
/// saved for this account" — the user may keep one in iCloud Keychain or on a
/// hardware key, so this is an opportunity, never a deficiency.
nonisolated struct PasskeyOpportunityRule: nonisolated AuditRule {
    let id = "auth.passkey-available"
    let version = 1
    let category = AuditCategory.authentication

    func evaluate(_ snapshot: VaultAuditSnapshot, context: AuditContext) async throws -> [AuditFinding] {
        snapshot.activeItems.compactMap { item in
            guard item.category == .login, !item.hasPasskey,
                  ServiceCapabilityCatalog.capability(urls: item.rawURLs)?.supportsPasskey == true
            else { return nil }
            return AuditFinding(
                ruleID: id,
                ruleVersion: version,
                severity: .low,
                category: category,
                affectedItemIDs: [item.id],
                // Catalog version in the fingerprint: updated data re-surfaces
                // the finding instead of inheriting a stale user decision.
                fingerprint: AuditFingerprint.make(
                    ruleID: id, version: version, itemIDs: [item.id],
                    marker: ServiceCapabilityCatalog.fingerprintMarker),
                titleKey: "finding.auth.passkey-available.title",
                detail: nil,
                remediation: .addPasskey,
                estimatedFixSeconds: AuditFixEstimate.enablePasskeyOrTOTP,
                detectedAt: context.now)
        }
    }
}
