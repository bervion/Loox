import SwiftUI

/// The Run Vault Audit flow: preflight checklist → live progress → result.
/// One pushed screen with internal phases (no fake scan: stages tick as the
/// real rules finish; only the known-leak stage takes observable time).
struct VaultAuditFlowScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let controller: AuditRunController
    /// Routes a result-screen destination (Fix Queue / full report) through the
    /// owner's navigator. This screen may sit inside a UIKit shell push where a
    /// value-based `NavigationLink` has no registered destination and taps
    /// would silently do nothing — the owner knows how to navigate; this
    /// screen must not guess.
    let openCategory: (WatchtowerCategory) -> Void

    var body: some View {
        Group {
            switch controller.phase {
            case .idle: preflight
            case .running(let stage, let completed, let total):
                running(stage: stage, completed: completed, total: total)
            case .finished: result
            }
        }
        .themedFormBackground()
        .navigationTitle(Text("Vault Audit"))
        .platformNavigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Preflight

    private var preflight: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text("Loox will review:")
                    .vaultType(.headline)
                    .themedForeground(.primary)

                VStack(alignment: .leading, spacing: Space.s3) {
                    checklistRow("Password strength")
                    checklistRow("Reused and duplicate passwords")
                    if env.settings.hibpEnabled { checklistRow("Passwords found in known leaks") }
                    checklistRow("Old and incomplete credentials")
                    checklistRow("Passkeys and verification codes")
                    checklistRow("Duplicate and conflicting items")
                }
                .themedCard()

                Text("Most checks happen on this device.")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)

                if env.settings.hibpEnabled {
                    VaultInfoBanner(.info, icon: Icons.shield,
                                    text: "Known-leak checks use privacy-preserving queries. Your full password is never sent.")
                }

                // The style owns sizing and typography — a sized label on top of
                // it doubles the button height (the "oversized CTA" defect).
                Button {
                    controller.start(env: env)
                    Haptics.tap()
                } label: {
                    Text("Start Audit").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
            }
            .padding(Space.gutter)
        }
    }

    private func checklistRow(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(Icons.checkCircle, size: Metric.iconInline)
                .themedForeground(.success)
            Text(title)
                .vaultType(.body)
                .themedForeground(.primary)
        }
    }

    // MARK: - Running

    private func running(stage: String, completed: Int, total: Int) -> some View {
        VStack(spacing: Space.s6) {
            Spacer()
            ProgressView(value: Double(completed), total: Double(max(total, 1)))
                .progressViewStyle(.linear)
                .padding(.horizontal, Space.s8)

            VStack(spacing: Space.s2) {
                Text("Reviewing your vault privately")
                    .vaultType(.headline)
                    .themedForeground(.primary)
                if !stage.isEmpty {
                    Text(AuditFindingCopy.stageTitle(ruleID: stage))
                        .vaultType(.callout)
                        .themedForeground(.secondary)
                        .contentTransition(.opacity)
                }
                Text(verbatim: appString("\(completed) of \(total) checks"))
                    .vaultType(.footnote)
                    .themedForeground(.tertiary)
                    .monospacedDigit()
            }
            Spacer()

            Button {
                controller.cancel()
                dismiss()
            } label: {
                Text("Cancel")
            }
            .buttonStyle(.themedTinted)
            .padding(.bottom, Space.s6)
        }
    }

    // MARK: - Result

    @ViewBuilder
    private var result: some View {
        if let report = controller.lastRun {
            AuditResultView(report: report, previousScore: controller.previousScore,
                            openCategory: openCategory) {
                controller.acknowledgeResult()
                dismiss()
            }
        } else {
            // Unreachable in practice; a safe fallback beats a blank screen.
            VStack(spacing: Space.s4) {
                Text("Audit complete").vaultType(.headline)
                Button { dismiss() } label: { Text("Done") }
                    .buttonStyle(.themedTinted)
            }
        }
    }
}

/// Result summary: score with delta, issue counts, rule-based fix estimate.
private struct AuditResultView: View {
    @Environment(AppEnvironment.self) private var env
    let report: AuditReport
    let previousScore: Int?
    let openCategory: (WatchtowerCategory) -> Void
    let done: () -> Void

    private var sections: AuditGroupSections {
        AuditGroupSections.from(report: report, dismissed: dismissedFingerprints)
    }

    private var dismissedFingerprints: Set<String> {
        guard let key = env.session.vaultKey else { return [] }
        return AuditReportStore(store: env.store).hiddenFingerprints(
            for: report.findings,
            personaID: env.repository.activePersona?.id, key: key)
    }

    private var estimatedFixMinutes: Int {
        let seconds = report.findings
            .filter { AuditGroupRow.bucket(for: $0.severity) == .actNow }
            .reduce(0) { $0 + $1.estimatedFixSeconds }
        return max(1, Int((Double(seconds) / 60).rounded(.up)))
    }

    var body: some View {
        // Left-aligned, top-anchored (DNA: typography is architecture — bold and
        // leading at key moments, not a centered float). One filled primary; the
        // report link is a quiet inline disclosure, never a third button.
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(verbatim: "\(report.score)")
                            .vaultType(.largeTitle)
                            .monospacedDigit()
                            .themedForeground(.primary)
                            .contentTransition(.numericText())
                        Text(verbatim: appString("out of 1000"))
                            .vaultType(.footnote)
                            .themedForeground(.tertiary)
                    }
                    Text(scoreBand(for: report.score).label)
                        .vaultType(.callout)
                        .themedForeground(scoreBand(for: report.score).role)
                    if let previousScore, previousScore != report.score {
                        Text(verbatim: "\(previousScore) → \(report.score)")
                            .vaultType(.footnote)
                            .themedForeground(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s2) {
                    summaryRow(count: sections.actNowCount, label: "important issues")
                    summaryRow(count: sections.improveCount, label: "recommended improvements")
                    if report.confidenceLimited {
                        Text(verbatim: appString("Based on \(report.analyzedItemCount) items"))
                            .vaultType(.footnote)
                            .themedForeground(.tertiary)
                    }
                    if !report.onlineChecksCompleted {
                        Text("Local checks are complete. Known-leak checks need an internet connection.")
                            .vaultType(.footnote)
                            .themedForeground(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if sections.actNowCount > 0 {
                        Text(verbatim: appString("Estimated fix time: \(estimatedFixMinutes) minutes"))
                            .vaultType(.footnote)
                            .themedForeground(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .themedCard()

                // Rank: with open issues the one next action is fixing them;
                // Done demotes to the quiet secondary. With none, Done IS the action.
                if sections.actNowCount > 0 {
                    Button { openCategory(.fixQueue) } label: {
                        Text("Fix important issues").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)

                    Button { done() } label: {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedTinted)
                } else {
                    Button { done() } label: {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.themedProminent)
                }

                Button { openCategory(.fullReport) } label: {
                    HStack(spacing: Space.s1) {
                        Text("View full report").vaultType(.subhead)
                        PolarisIcon(Icons.chevronRight, size: 12)
                    }
                    .themedForeground(.accentText)
                    .frame(minHeight: Metric.hitMin)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(Space.gutter)
        }
    }

    private func summaryRow(count: Int, label: String.LocalizationValue) -> some View {
        HStack(spacing: Space.s2) {
            Text(verbatim: "\(count)")
                .vaultType(.headline)
                .monospacedDigit()
                .themedForeground(count > 0 ? .primary : .secondary)
            Text(verbatim: appString(label))
                .vaultType(.body)
                .themedForeground(.secondary)
        }
    }
}
