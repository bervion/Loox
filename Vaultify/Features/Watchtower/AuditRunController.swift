import SwiftUI

/// Drives one Vault Audit run for the UI: builds the snapshot from the active
/// persona, runs the coordinator on a DETACHED task (off-main — see the
/// comment at the Task.detached site) with live stage progress, scores the
/// result, and persists the report. A cancelled or failed run records nothing;
/// a lock mid-run also records nothing (fresh key check before save).
@MainActor @Observable final class AuditRunController {

    enum Phase: Equatable {
        case idle
        case running(stageRuleID: String, completed: Int, total: Int)
        case finished
    }

    private(set) var phase: Phase = .idle
    /// Report of the audit completed in THIS session (full findings, not digests).
    private(set) var lastRun: AuditReport?
    /// Score of the previous saved report — the "874 → 912" delta on the result
    /// screen. Captured at run start so the comparison is against pre-run state.
    private(set) var previousScore: Int?

    private var task: Task<Void, Never>?

    func start(env: AppEnvironment) {
        guard phase == .idle || phase == .finished else { return }
        guard let key = env.session.vaultKey else { return }

        let reportStore = AuditReportStore(store: env.store)
        let personaID = env.repository.activePersona?.id
        previousScore = reportStore.latest(personaID: personaID, key: key)?.score
        let daysSince = reportStore.daysSinceLastCompletedAudit(personaID: personaID)

        let items = env.repository.activePersonaItems
        let snapshot = VaultAuditSnapshot.make(items: items, personaID: personaID,
                                               passkeyItemIDs: Self.passkeyItemIDs(
                                                   items: items, passkeys: env.repository.passkeys))
        var rules = AuditRuleRegistry.localRules()
        let online = env.settings.hibpEnabled
        if online { rules.append(PwnedPasswordRule()) }
        let coordinator = AuditCoordinator(rules: rules)
        // Vault-key-derived HMAC key: secret-derived fingerprint markers sync
        // as plaintext CK record names and must not be unkeyed hashes.
        let markerKey = key.withUnsafeBytes { AuditFingerprint.markerKey(fromVaultKey: Array($0)) }
        let context = AuditContext(onlineChecksEnabled: online, secretMarkerKey: markerKey)

        phase = .running(stageRuleID: "", completed: 0, total: rules.count)
        let session = env.session
        let store = env.store
        // Task.detached is REQUIRED here, not style: with Approachable
        // Concurrency (NonisolatedNonsendingByDefault) a plain `Task {}` from
        // this @MainActor type would run the whole engine — matchers, SHA-1
        // hashing, scoring — on the main thread.
        task = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let run = try await coordinator.run(snapshot: snapshot, context: context) { p in
                    Task { @MainActor [weak self] in
                        guard let self, case .running = self.phase else { return }
                        self.phase = .running(stageRuleID: p.ruleID,
                                              completed: p.completedRules, total: p.totalRules)
                    }
                }
                let report = ScoringEngine.report(snapshot: snapshot, run: run,
                                                  daysSinceLastCompletedAudit: daysSince)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    // The vault may have locked while the audit ran: record
                    // nothing after lock (fresh key read, never the captured one).
                    guard let freshKey = session.vaultKey else {
                        phase = .idle
                        return
                    }
                    try? AuditReportStore(store: store)
                        .save(report: report, personaID: personaID, key: freshKey)
                    lastRun = report
                    phase = .finished
                    Haptics.success()
                }
            } catch {
                // Cancelled (or failed before any result): no report is recorded.
                await MainActor.run { [weak self] in self?.phase = .idle }
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Back to the preflight state (keeps `lastRun` for the overview).
    func acknowledgeResult() {
        if phase == .finished { phase = .idle }
    }

    /// Items considered passkey-protected: any saved passkey whose relying
    /// party matches one of the item's website hosts.
    private static func passkeyItemIDs(items: [VaultItem], passkeys: [PasskeyInfo]) -> Set<String> {
        let relyingParties = Set(passkeys.map { $0.relyingParty.lowercased() })
        guard !relyingParties.isEmpty else { return [] }
        return Set(items.filter { item in
            item.fields.contains { field in
                guard field.kind == .url,
                      let host = DomainNormalizer.normalizedHost(from: field.value) else { return false }
                return relyingParties.contains { host == $0 || host.hasSuffix("." + $0) }
            }
        }.map(\.id))
    }
}
