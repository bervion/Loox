import Foundation

/// The last saved audit's findings that name ONE item — the source for the item
/// detail warning banner (`ItemAttentionBanner`).
///
/// Reads the most recent persisted report and nothing else: no rules re-run, no
/// network, no HIBP request from a detail screen. That is what makes leak findings
/// available at all — the known-leak check needs the network, so its verdict can
/// only come from an audit the user already ran.
///
/// The user's own decisions are honored the same way every Watchtower surface does
/// it (`AuditReportStore.hiddenFingerprints`): a dismissed or still-snoozed finding
/// stays dismissed here too, and a bumped rule version resurfaces it.
///
/// Freshness is the CALLER's job: findings carry `completedAt` so the view can drop
/// a verdict the user has already acted on (a password changed after the audit ran,
/// a verification code added since). Nothing here re-derives the vault state.
struct ItemAuditFindings {
    let findings: [QueuedFinding]
    /// When the audit that produced these findings finished.
    let completedAt: Date
    /// Rule versions from that report — an Ignore records the version it was decided
    /// under, so a later rule version resurfaces the finding instead of staying
    /// silently dismissed.
    var ruleVersions: [String: Int] = [:]

    static let none = ItemAuditFindings(findings: [], completedAt: .distantPast)

    /// Every item the latest report found in a known leak, for Home's "Needs
    /// Attention" section — the vault-wide sibling of `load(itemID:)`, honoring
    /// the same dismissals. Empty set when locked or never audited; the caller
    /// applies the password-changed-since staleness rule per item.
    static func leakedIndex(env: AppEnvironment) -> (itemIDs: Set<String>, completedAt: Date) {
        guard let key = env.session.vaultKey else { return ([], .distantPast) }
        let personaID = env.repository.activePersona?.id
        let reportStore = AuditReportStore(store: env.store)
        guard let payload = reportStore.latest(personaID: personaID, key: key) else {
            return ([], .distantPast)
        }
        let leaked = payload.findings.filter { $0.ruleID == "exposure.leaked" }
        guard !leaked.isEmpty else { return ([], payload.completedAt) }
        let hidden = reportStore.hiddenFingerprints(
            fingerprints: leaked.map { ($0.fingerprint, $0.ruleID) },
            ruleVersions: payload.ruleVersions,
            personaID: personaID, key: key)
        let ids = leaked.filter { !hidden.contains($0.fingerprint) }
            .reduce(into: Set<String>()) { $0.formUnion($1.affectedItemIDs) }
        return (ids, payload.completedAt)
    }

    /// Open findings for `itemID` from the latest report, or `.none` when the vault
    /// is locked, no audit has ever run, or nothing names this item.
    static func load(itemID: String, env: AppEnvironment) -> ItemAuditFindings {
        guard let key = env.session.vaultKey else { return .none }
        let personaID = env.repository.activePersona?.id
        let reportStore = AuditReportStore(store: env.store)
        guard let payload = reportStore.latest(personaID: personaID, key: key) else { return .none }

        let mine = payload.findings.filter { $0.affectedItemIDs.contains(itemID) }
        guard !mine.isEmpty else {
            return ItemAuditFindings(findings: [], completedAt: payload.completedAt)
        }
        let hidden = reportStore.hiddenFingerprints(
            fingerprints: mine.map { ($0.fingerprint, $0.ruleID) },
            ruleVersions: payload.ruleVersions,
            personaID: personaID, key: key)
        return ItemAuditFindings(
            findings: mine.filter { !hidden.contains($0.fingerprint) }.map(QueuedFinding.init),
            completedAt: payload.completedAt,
            ruleVersions: payload.ruleVersions)
    }
}
