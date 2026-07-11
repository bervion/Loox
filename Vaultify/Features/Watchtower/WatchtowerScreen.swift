import SwiftUI

/// Typed navigation values for the Security tab drill-downs.
/// Declared at file scope (not private) so NavigationLink can infer the type.
enum WatchtowerCategory: Hashable {
    /// The "Overall password strength" card → per-item strength breakdown.
    case strength
    /// The Run Vault Audit flow (preflight → running → result).
    case audit
    /// Pillar breakdown behind the score (tap the ring).
    case whyScore
    /// Full report of the latest audit.
    case fullReport
    /// All findings of one rule (ruleID payload).
    case findingGroup(String)
    /// Sequential remediation queue ("Fix important issues").
    case fixQueue
    /// Score trend across saved audits.
    case history
    /// Diff of one history entry (index into the newest-first list).
    case historyDetail(Int)
}

/// Security — vault health overview (user-facing name; the code keeps the
/// Watchtower prefix). Shows the LATEST COMPLETED audit: score ring, the three
/// action groups (Act now / Improve / Maintain), and the Run Vault Audit entry.
/// The score only ever changes when an audit completes (verify-first, never
/// optimistic).
struct WatchtowerScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(UIStateStore.self) private var uiState

    @State private var controller = AuditRunController()
    @State private var latestPayload: AuditReportPayload?
    @State private var health = VaultHealth.empty     // strength card + empty state
    @State private var editorTarget: EditorTarget?
    @State private var scrolledUnder = false
    /// Bumped when new audit data arrives so the gauge intro replays (see
    /// `WatchtowerIntroGate` — tab switches alone never replay it).
    @State private var refreshCount = 0

    /// Data-context identity for the intro animations: persona switch or a
    /// completed audit changes it; a mere tab revisit does not.
    private var introKey: String {
        "\(env.repository.activePersona?.id ?? "-")|\(refreshCount)"
    }

    private var personaID: String? { env.repository.activePersona?.id }

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

    private var dismissedFingerprints: Set<String> {
        Set(env.store.findingStates(personaID: personaID)
            .filter { $0.value.status != FindingStatus.open.rawValue }
            .map(\.key))
    }

    private var emptyVault: Bool {
        health.analyzedCount == 0 && env.repository.activePersonaItems.isEmpty
    }

    var body: some View {
        @Bindable var uiState = uiState
        return NavigationStack(path: $uiState.watchtowerPath) {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Top inset clears the floating header + reports scroll-edge state.
                        VaultHeaderScrollSpacer(scrolledUnder: $scrolledUnder)

                        ringSection
                        contentSection
                    }
                    .padding(.bottom, Space.s10)
                }
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .refreshable { reload() }

                // Floating header overlays the scroll content — glass blurs beneath.
                VaultScreenHeader("Security") {
                    HeaderActionCluster {
                        Menu {
                            ForEach(ItemCategory.allCases) { category in
                                Button {
                                    editorTarget = .new(category)
                                } label: {
                                    Label { Text(category.title) } icon: { PolarisIcon(category.iconAsset) }
                                }
                            }
                        } label: {
                            PolarisIcon(Icons.pageAdd, size: Metric.iconUtility)
                                .themedForeground()
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .frame(width: Metric.hitMin, height: Metric.hitMin)
                        .accessibilityLabel(Text("Add Item"))
                    }
                }
            }
            .environment(\.vaultHeaderScrolledUnder, scrolledUnder)
            .themedWallpaper(env.theme.wallpaper,
                             fallback: Color(rgb: env.theme.active.groupedBackground))
            .platformHiddenNavigationBar()
            .sheet(item: $editorTarget) { ItemEditorScreen(target: $0) }
            .navigationDestination(for: String.self) { itemID in
                ItemDetailScreen(itemID: itemID)
            }
            .navigationDestination(for: WatchtowerCategory.self) { category in
                categoryScreen(for: category)
            }
            .task { reload() }
            // Security audits the ACTIVE persona's vault — switching persona reloads.
            .onChange(of: env.repository.activePersona?.id) { reload() }
            .onChange(of: env.repository.items.count) {
                health = PasswordAudit.analyze(env.repository.activePersonaItems)
            }
            // A completed run IS a data moment: refresh the payload + replay intro.
            .onChange(of: controller.phase) { _, phase in
                if phase == .finished { reload() }
            }
            // Lock mid-run: the plaintext snapshot inside the running task must
            // not outlive the session — cancel immediately.
            .onChange(of: env.session.vaultKey == nil) { _, locked in
                if locked { controller.cancel() }
            }
        }
    }

    private func reload() {
        health = PasswordAudit.analyze(env.repository.activePersonaItems)
        if let key = env.session.vaultKey {
            latestPayload = AuditReportStore(store: env.store).latest(personaID: personaID, key: key)
        }
        refreshCount += 1
    }

    // MARK: - Destinations

    @ViewBuilder
    private func categoryScreen(for category: WatchtowerCategory) -> some View {
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

    /// Queue source: full findings from this session's run, else saved digests.
    private var queuedFindings: [QueuedFinding] {
        if let report = controller.lastRun { return report.findings.map(QueuedFinding.init) }
        return latestPayload?.findings.map(QueuedFinding.init) ?? []
    }

    @ViewBuilder
    private func findingGroupScreen(ruleID: String) -> some View {
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

    // MARK: - Score ring + audit meta

    private var ringSection: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                NavigationLink(value: WatchtowerCategory.whyScore) {
                    WatchtowerScoreRing(score: latestPayload?.score ?? 0, introKey: introKey)
                }
                .buttonStyle(.plain)
                .disabled(latestPayload == nil)
                .accessibilityLabel(Text("Vault Health"))
                .accessibilityHint(Text("Why this score"))
                Spacer()
            }
            .padding(.vertical, Space.s2)

            VStack(spacing: Space.s1) {
                if let latestPayload {
                    Text(verbatim: lastAuditedText(latestPayload.completedAt))
                        .vaultType(.footnote)
                        .themedForeground(.tertiary)
                    if latestPayload.confidenceLimited {
                        Text(verbatim: appString("Based on \(latestPayload.analyzedItemCount) items"))
                            .vaultType(.footnote)
                            .themedForeground(.tertiary)
                    }
                } else if !emptyVault {
                    Text("Run your first audit to see your vault's health score.")
                        .vaultType(.callout)
                        .themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.s7)
                }
            }
            .padding(.bottom, Space.s3)
        }
    }

    private func lastAuditedText(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        return days == 0
            ? appString("Last audited today")
            : appString("Last audited \(days) days ago")
    }

    // MARK: - Main content

    @ViewBuilder
    private var contentSection: some View {
        VStack(spacing: Space.s5) {
            // One filled primary; the resume path is the quiet tinted secondary
            // (the style owns typography and height — plain Text labels only).
            if !emptyVault {
                NavigationLink(value: WatchtowerCategory.audit) {
                    Text("Run Vault Audit").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                .padding(.horizontal, Space.gutter)
            }

            if let sections, sections.actNowCount > 0 {
                NavigationLink(value: WatchtowerCategory.fixQueue) {
                    Text(verbatim: appString("Continue fixing \(sections.actNowCount) issues"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedTinted)
                .padding(.horizontal, Space.gutter)
            }

            NavigationLink(value: WatchtowerCategory.strength) {
                WatchtowerStrengthCard(overallStrength: health.overallStrength, introKey: introKey)
            }
            .buttonStyle(PressableSurfaceStyle(theme: env.theme.active,
                                               base: Color(rgb: env.theme.active.elevatedBackground),
                                               cornerRadius: Radius.lg, bordered: true))
            .padding(.horizontal, Space.gutter)

            if emptyVault {
                emptyVaultView
            } else if let sections, !sections.isEmpty {
                if !sections.actNow.isEmpty {
                    AuditGroupSectionView(title: LocalizedStringResource("Act now").inAppLocalized,
                                          rows: sections.actNow, tintRole: .destructive)
                }
                if !sections.improve.isEmpty {
                    AuditGroupSectionView(title: LocalizedStringResource("Improve").inAppLocalized,
                                          rows: sections.improve, tintRole: .warning)
                }
                if !sections.maintain.isEmpty {
                    AuditGroupSectionView(title: LocalizedStringResource("Maintain").inAppLocalized,
                                          rows: sections.maintain, tintRole: .accent)
                }
            } else if sections != nil {
                allClearView
            }

            if latestPayload != nil {
                NavigationLink(value: WatchtowerCategory.history) {
                    HStack(spacing: Space.s3) {
                        PolarisIcon(Icons.clock, size: Metric.iconInline)
                            .themedForeground(.secondary)
                        Text("Audit history")
                            .vaultType(.body)
                            .themedForeground(.primary)
                        Spacer()
                        PolarisIcon(Icons.chevronRight, size: 14)
                            .themedForeground(.tertiary)
                    }
                    .padding(Space.s4)
                    .contentShape(.rect)
                }
                .buttonStyle(PressableSurfaceStyle(theme: env.theme.active,
                                                   base: Color(rgb: env.theme.active.elevatedBackground),
                                                   cornerRadius: Radius.lg, bordered: true))
                .padding(.horizontal, Space.gutter)
            }

            hibpToggleSection
        }
        .padding(.top, Space.s4)
    }

    // MARK: - Empty vault / all clear

    private var emptyVaultView: some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(Icons.shield, size: Metric.iconInline)
                .themedForeground(.secondary)
            Text("Add a password to see your vault's security score.")
                .vaultType(.callout)
                .themedForeground(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
        .padding(.horizontal, Space.gutter)
    }

    private var allClearView: some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(Icons.checkCircle, size: Metric.iconInline)
                .themedForeground(.success)
            Text("Excellent vault health. No open issues in the last audit.")
                .vaultType(.callout)
                .themedForeground(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
        .padding(.horizontal, Space.gutter)
    }

    // MARK: - HIBP toggle

    private var hibpBinding: Binding<Bool> {
        Binding(
            get: { env.settings.hibpEnabled },
            set: { env.settings.hibpEnabled = $0 })
    }

    private var hibpToggleSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Toggle(isOn: hibpBinding) {
                Text("Check for known breaches")
            }
            .toggleStyle(.themed)

            Text("Uses k-anonymity. Only the first five characters of each password's SHA-1 hash are sent. Passwords never leave your device.")
                .vaultType(.footnote)
                .themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .themedCard()
        .padding(.horizontal, Space.gutter)
    }
}
