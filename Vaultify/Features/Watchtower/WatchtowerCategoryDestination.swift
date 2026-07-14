import SwiftUI

/// Security drill-down destinations, hoisted out of `WatchtowerScreen` so they
/// live on the app-wide root navigation stack (Telegram-style: pushes cover the
/// tab bar). Loads the latest audit payload itself; the live audit `controller`
/// is shared from the tab shell so a running audit stays connected.
struct WatchtowerCategoryDestination: View {
    let category: WatchtowerCategory
    let controller: AuditRunController
    @Environment(AppEnvironment.self) private var env

    private var personaID: String? { env.repository.activePersona?.id }

    private var latestPayload: AuditReportPayload? {
        guard let key = env.session.vaultKey else { return nil }
        return AuditReportStore(store: env.store).latest(personaID: personaID, key: key)
    }

    private var dismissedFingerprints: Set<String> {
        Set(env.store.findingStates(personaID: personaID)
            .filter { $0.value.status != FindingStatus.open.rawValue }
            .map(\.key))
    }

    private var sections: AuditGroupSections? {
        let dismissed = dismissedFingerprints
        if let report = controller.lastRun {
            return AuditGroupSections.from(report: report, dismissed: dismissed)
        }
        if let latestPayload {
            return AuditGroupSections.from(payload: latestPayload, dismissed: dismissed)
        }
        return nil
    }

    private var queuedFindings: [QueuedFinding] {
        if let report = controller.lastRun { return report.findings.map(QueuedFinding.init) }
        return latestPayload?.findings.map(QueuedFinding.init) ?? []
    }

    var body: some View {
        switch category {
        case .strength:
            WatchtowerStrengthScreen()
        case .audit:
            VaultAuditFlowScreen(controller: controller)
        case .whyScore:
            if let latestPayload { WhyThisScoreScreen(payload: latestPayload) }
        case .fullReport:
            if let latestPayload { AuditFullReportScreen(payload: latestPayload) }
        case .findingGroup(let ruleID):
            findingGroupScreen(ruleID: ruleID)
        case .fixQueue:
            AuditFixQueueScreen(findings: queuedFindings,
                                ruleVersions: controller.lastRun?.ruleVersions
                                    ?? latestPayload?.ruleVersions ?? [:])
        case .history:
            AuditHistoryScreen()
        case .historyDetail(let index):
            AuditHistoryDetailScreen(index: index)
        }
    }

    @ViewBuilder private func findingGroupScreen(ruleID: String) -> some View {
        let itemIDs = sections.map {
            ($0.actNow + $0.improve + $0.maintain).first { $0.ruleID == ruleID }?.itemIDs ?? []
        } ?? []
        let itemsByID = Dictionary(uniqueKeysWithValues: env.repository.activePersonaItems
            .map { ($0.id, $0) })
        let issues = itemIDs.compactMap { itemsByID[$0] }.map { item in
            VaultIssue(itemID: item.id,
                       itemTitle: item.title.isEmpty ? appString("Untitled") : item.title,
                       category: item.category, kind: .weak, detail: nil)
        }
        WatchtowerCategoryScreen(
            title: AuditFindingCopy.title(ruleID: ruleID),
            issues: issues,
            infoNote: LocalizedStringKey(String(localized: AuditFindingCopy.explanation(ruleID: ruleID))))
    }
}
