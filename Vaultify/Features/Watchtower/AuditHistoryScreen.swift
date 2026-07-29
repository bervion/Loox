import SwiftUI

/// Audit history: score trend with deltas, tap-through to a per-run diff
/// (what got resolved, what is new). Data is the persona's saved reports.
struct AuditHistoryScreen: View {
    @Environment(AppEnvironment.self) private var env

    @State private var history: [AuditReportPayload] = []

    var body: some View {
        Group {
            if history.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(Array(history.enumerated()), id: \.element.completedAt) { index, payload in
                        let previous = index + 1 < history.count ? history[index + 1] : nil
                        NavigationLink(value: WatchtowerCategory.historyDetail(index)) {
                            row(payload: payload, previous: previous)
                        }
                        .listRowBackground(VaultColors.surface)
                        .disabled(previous == nil)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .themedFormBackground()
        .navigationTitle(Text("Audit history"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        guard let key = env.session.vaultKey else { return }
        history = AuditReportStore(store: env.store)
            .history(personaID: env.repository.activePersona?.id, key: key)
    }

    private func row(payload: AuditReportPayload, previous: AuditReportPayload?) -> some View {
        HStack(spacing: Space.s3) {
            Text(payload.completedAt, format: .dateTime.day().month().year())
                .vaultType(.body)
                .themedForeground(.primary)
            Spacer()
            if let previous, previous.score != payload.score {
                let delta = payload.score - previous.score
                Text(verbatim: delta > 0 ? "+\(delta)" : "\(delta)")
                    .vaultType(.footnote)
                    .monospacedDigit()
                    .themedForeground(delta > 0 ? .success : .destructive)
            }
            Text(verbatim: "\(payload.score)")
                .vaultType(.headline)
                .monospacedDigit()
                .themedForeground(.primary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Same leading card shape as the Security overview's empty state —
    /// empty is an intentional state, not a centered float.
    private var emptyState: some View {
        VStack {
            HStack(spacing: Space.s3) {
                VaultIcon(Icons.shield, size: Metric.iconInline)
                    .themedForeground(.secondary)
                Text("Run your first audit to start tracking progress.")
                    .vaultType(.callout)
                    .themedForeground(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()
            .padding(Space.gutter)
            Spacer()
        }
    }
}

/// Diff of one history entry against the run before it.
struct AuditHistoryDetailScreen: View {
    @Environment(AppEnvironment.self) private var env
    /// Index into the newest-first history list.
    let index: Int

    @State private var diff: AuditHistoryDiff.Diff?
    @State private var payload: AuditReportPayload?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                if let payload {
                    HStack(spacing: Space.s2) {
                        Text(verbatim: "\(payload.score)")
                            .vaultType(.largeTitle)
                            .monospacedDigit()
                            .themedForeground(.primary)
                        Text(payload.completedAt, format: .dateTime.day().month().year())
                            .vaultType(.footnote)
                            .themedForeground(.tertiary)
                    }
                }
                if let diff {
                    if !diff.resolved.isEmpty {
                        diffSection("Resolved", rows: diff.resolved, role: .success)
                    }
                    if !diff.noLongerMonitored.isEmpty {
                        diffSection("No longer monitored", rows: diff.noLongerMonitored,
                                    role: .secondary)
                    }
                    if !diff.new.isEmpty {
                        diffSection("New", rows: diff.new, role: .warning)
                    }
                    if diff.isEmpty {
                        Text("No changes compared with the previous audit.")
                            .vaultType(.callout)
                            .themedForeground(.secondary)
                    }
                }
            }
            .padding(Space.gutter)
        }
        .themedFormBackground()
        .navigationTitle(Text("Changes"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        guard let key = env.session.vaultKey else { return }
        let history = AuditReportStore(store: env.store)
            .history(personaID: env.repository.activePersona?.id, key: key)
        guard index < history.count else { return }
        payload = history[index]
        guard index + 1 < history.count else { return }
        let itemIDs = Set(env.repository.activePersonaItems.map(\.id))
        diff = AuditHistoryDiff.diff(previous: history[index + 1], current: history[index],
                                     currentItemIDs: itemIDs)
    }

    private func diffSection(_ title: LocalizedStringResource,
                             rows: [AuditHistoryDiff.RuleCount],
                             role: ThemeRole) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(rows) { row in
                    HStack(spacing: Space.s2) {
                        Text(verbatim: "\(row.count)")
                            .vaultType(.headline)
                            .monospacedDigit()
                            .themedForeground(role)
                        Text(AuditFindingCopy.title(ruleID: row.ruleID))
                            .vaultType(.body)
                            .themedForeground(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()
        }
    }
}
