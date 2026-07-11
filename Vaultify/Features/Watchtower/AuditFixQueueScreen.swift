import SwiftUI

/// "Fix important issues" — walks the deterministic remediation queue one
/// finding at a time. Nothing is ever marked fixed here: the user acts, and
/// only a re-run audit confirms resolution (verify-first).
struct AuditFixQueueScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let findings: [QueuedFinding]
    /// ruleID → version from the source report (dismissals record the version
    /// they were made under, so rule upgrades resurface them).
    let ruleVersions: [String: Int]

    @State private var index = 0
    @State private var editorTarget: EditorTarget?
    @State private var showDismissOptions = false

    private var queue: [QueuedFinding] {
        FixQueuePlanner.queue(findings: findings, dismissed: dismissedFingerprints)
    }

    private var dismissedFingerprints: Set<String> {
        Set(env.store.findingStates(personaID: env.repository.activePersona?.id)
            .filter { $0.value.status != FindingStatus.open.rawValue }
            .map(\.key))
    }

    var body: some View {
        Group {
            if index < queue.count {
                FindingDetailView(finding: queue[index],
                                  position: index + 1,
                                  total: queue.count,
                                  editorTarget: $editorTarget,
                                  showDismissOptions: $showDismissOptions) {
                    advance()
                }
            } else {
                completed
            }
        }
        .themedFormBackground()
        .navigationTitle(Text("Fix issues"))
        .platformNavigationBarTitleDisplayMode(.inline)
        .sheet(item: $editorTarget) { ItemEditorScreen(target: $0) }
        .confirmationDialog(Text("Stop reminders for this finding"),
                            isPresented: $showDismissOptions, titleVisibility: .visible) {
            dismissActions
        } message: {
            Text("Loox will stop reminding you about this finding. It returns if the underlying check changes.")
        }
    }

    private func advance() {
        if index + 1 <= queue.count { index += 1 }
    }

    // MARK: - Dismiss options (proposal §15 — reason is recorded)

    @ViewBuilder
    private var dismissActions: some View {
        Button { setState(.ignored, reason: "remind-later",
                          snooze: Date(timeIntervalSinceNow: 30 * 24 * 3600)) } label: {
            Text("Remind me later")
        }
        Button { setState(.ignored, reason: "ignored") } label: {
            Text("Ignore this finding")
        }
        Button { setState(.acceptedRisk, reason: "not-account-password") } label: {
            Text("This is not an account password")
        }
        Button { setState(.acceptedRisk, reason: "account-unused") } label: {
            Text("I no longer use this account")
        }
        Button(role: .cancel) {} label: { Text("Cancel") }
    }

    private func setState(_ status: FindingStatus, reason: String, snooze: Date? = nil) {
        guard index < queue.count, let key = env.session.vaultKey else { return }
        let finding = queue[index]
        let placeholder = AuditFinding(
            ruleID: finding.ruleID,
            ruleVersion: ruleVersions[finding.ruleID] ?? 1,
            severity: finding.severity, category: .quality,
            affectedItemIDs: finding.itemIDs, fingerprint: finding.fingerprint,
            titleKey: "", detail: nil, remediation: .reviewItem,
            estimatedFixSeconds: 0, detectedAt: .now)
        try? AuditReportStore(store: env.store)
            .setState(status, reason: reason, snoozedUntil: snooze,
                      for: placeholder, personaID: env.repository.activePersona?.id, key: key)
        Haptics.tap()
        // The queue recomputes without this fingerprint — index now points at
        // the next finding automatically.
    }

    // MARK: - Done state

    /// Completion state: top-anchored and leading like the app's other
    /// completion screens — one primary action, no centered float.
    private var completed: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: Space.s3) {
                PolarisIcon(Icons.checkCircle, size: Metric.iconUtility)
                    .themedForeground(.success)
                Text("You have walked the whole queue.")
                    .vaultType(.headline)
                    .themedForeground(.primary)
            }
            Text("Run the audit again to verify your fixes and update the score.")
                .vaultType(.callout)
                .themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                dismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .padding(.top, Space.s2)
        }
        .padding(Space.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Finding detail

/// One finding: what it is, why it matters, the affected items, and the
/// actions that actually remediate it.
private struct FindingDetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL

    let finding: QueuedFinding
    let position: Int
    let total: Int
    @Binding var editorTarget: EditorTarget?
    @Binding var showDismissOptions: Bool
    let next: () -> Void

    private var items: [VaultItem] {
        let byID = Dictionary(uniqueKeysWithValues: env.repository.activePersonaItems
            .map { ($0.id, $0) })
        return finding.itemIDs.compactMap { byID[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                Text(verbatim: appString("\(position) of \(total)"))
                    .vaultType(.footnote)
                    .themedForeground(.tertiary)
                    .monospacedDigit()

                VStack(alignment: .leading, spacing: Space.s2) {
                    Text(AuditFindingCopy.title(ruleID: finding.ruleID))
                        .vaultType(.headline)
                        .themedForeground(.primary)
                    Text(AuditFindingCopy.explanation(ruleID: finding.ruleID))
                        .vaultType(.body)
                        .themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s2) {
                        Text("Affected items")
                            .vaultType(.sectionLabel)
                            .themedForeground(.secondary)
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                NavigationLink(value: item.id) {
                                    HStack(spacing: Space.s3) {
                                        CategoryBadge(category: item.category, size: 34)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(verbatim: item.title.isEmpty
                                                 ? appString("Untitled") : item.title)
                                                .vaultType(.body)
                                                .themedForeground(.primary)
                                                .lineLimit(1)
                                            Text(verbatim: item.updatedAt.formatted(
                                                date: .abbreviated, time: .omitted))
                                                .vaultType(.footnote)
                                                .themedForeground(.tertiary)
                                        }
                                        Spacer()
                                        PolarisIcon(Icons.chevronRight, size: 14)
                                            .themedForeground(.tertiary)
                                    }
                                    .padding(Space.s3)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(PressableSurfaceStyle(theme: env.theme.active))
                                if item.id != items.last?.id {
                                    ThemedDivider().padding(.leading, Space.gutter)
                                }
                            }
                        }
                        .themedCard(padding: 0)
                    }
                }

                actions
            }
            .padding(Space.gutter)
        }
    }

    /// Action hierarchy (DNA #7 — no button walls): remediation shortcuts are
    /// occasional extras in a compact utility row, "Next issue" is the ONE
    /// filled primary, dismiss is a quiet text action below it.
    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Space.s3) {
            HStack(spacing: Space.s3) {
                if let url = actionURL {
                    Button {
                        openURL(url)
                    } label: {
                        Text(finding.ruleID.hasPrefix("auth")
                             ? "Open security settings" : "Open website")
                    }
                    .buttonStyle(.themedCompact)
                }
                if let first = items.first {
                    Button {
                        editorTarget = .edit(first)
                    } label: {
                        Text("Edit item")
                    }
                    .buttonStyle(.themedCompact)
                }
                Spacer(minLength: 0)
            }

            Button {
                next()
                Haptics.tap()
            } label: {
                Text("Next issue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)

            Button {
                showDismissOptions = true
            } label: {
                Text("Dismiss this finding")
                    .vaultType(.subhead)
                    .frame(maxWidth: .infinity, minHeight: Metric.hitMin)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .themedForeground(.secondary)
        }
    }

    /// Security-settings deep link (auth findings) or the item's website.
    private var actionURL: URL? {
        let urls = items.flatMap { item in
            item.fields.filter { $0.kind == .url && !$0.isEmpty }.map(\.value)
        }
        if finding.ruleID.hasPrefix("auth"),
           let settings = ServiceCapabilityCatalog.capability(urls: urls)?.securitySettingsURL {
            return URL(string: settings)
        }
        guard finding.ruleID.hasPrefix("auth") || finding.ruleID == "exposure.leaked"
                || finding.ruleID.hasPrefix("quality") || finding.ruleID == "reuse.exact",
              var raw = urls.first else { return nil }
        if !raw.contains("://") { raw = "https://" + raw }
        return URL(string: raw)
    }
}
