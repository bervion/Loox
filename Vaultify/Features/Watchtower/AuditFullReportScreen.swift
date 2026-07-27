import SwiftUI

/// The complete report of the latest audit: what was reviewed, what needs
/// attention, what is healthy. Read-only; fixing happens from the overview.
struct AuditFullReportScreen: View {
    let payload: AuditReportPayload

    private var sections: AuditGroupSections {
        AuditGroupSections.from(payload: payload, dismissed: [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text(payload.completedAt, style: .date)
                    .vaultType(.footnote)
                    .themedForeground(.tertiary)

                reportSection("Reviewed") {
                    statRow(count: payload.analyzedItemCount, label: "items with passwords")
                    statRow(count: payload.uniquePasswordCount, label: "unique passwords")
                    statRow(count: payload.domainCount, label: "websites")
                }

                if !sections.actNow.isEmpty {
                    reportSection("Act now") {
                        ForEach(sections.actNow) { groupLine($0) }
                    }
                }
                if !sections.improve.isEmpty {
                    reportSection("Improve") {
                        ForEach(sections.improve) { groupLine($0) }
                    }
                }
                if !sections.maintain.isEmpty {
                    reportSection("Maintain") {
                        ForEach(sections.maintain) { groupLine($0) }
                    }
                }
                if sections.isEmpty {
                    reportSection("Healthy") {
                        HStack(spacing: Space.s3) {
                            PolarisIcon(Icons.checkCircle, size: Metric.iconInline)
                                .themedForeground(.success)
                            Text("No issues were found in this audit.")
                                .vaultType(.body)
                                .themedForeground(.secondary)
                        }
                    }
                }

                if !payload.onlineChecksCompleted {
                    // Honest severity: part of the audit did not run, so this
                    // report is incomplete. That is a caveat, not neutral info.
                    VaultInfoBanner(.warning,
                                    text: "Known-leak checks did not complete in this audit. Run the audit again with an internet connection.")
                }
            }
            .padding(Space.gutter)
        }
        .themedFormBackground()
        .navigationTitle(Text("Audit report"))
        .platformNavigationBarTitleDisplayMode(.inline)
    }

    private func reportSection(_ title: LocalizedStringResource,
                               @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(title)
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
            VStack(alignment: .leading, spacing: Space.s3, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .themedCard()
        }
    }

    private func statRow(count: Int, label: String.LocalizationValue) -> some View {
        HStack(spacing: Space.s2) {
            Text(verbatim: "\(count)")
                .vaultType(.headline)
                .monospacedDigit()
                .themedForeground(.primary)
            Text(verbatim: appString(label))
                .vaultType(.body)
                .themedForeground(.secondary)
        }
    }

    private func groupLine(_ row: AuditGroupRow) -> some View {
        HStack(spacing: Space.s2) {
            Text(verbatim: "\(row.findingCount)")
                .vaultType(.headline)
                .monospacedDigit()
                .themedForeground(.primary)
            Text(AuditFindingCopy.title(ruleID: row.ruleID))
                .vaultType(.body)
                .themedForeground(.secondary)
                .lineLimit(2)
        }
    }
}
