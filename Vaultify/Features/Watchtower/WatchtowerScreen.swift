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
    // Compact-iOS UIKit shell; nil on the iPad/Mac sidebar (SwiftUI-path fallback).
    @Environment(AppNavigator.self) private var navigator: AppNavigator?

    @State private var controller = AuditRunController()
    @State private var latestPayload: AuditReportPayload?
    @State private var health = VaultHealth.empty     // strength card + empty state
    @State private var editorTarget: EditorTarget?
    /// Item-type picker + the category chosen there (presented as the editor once
    /// the picker finishes dismissing).
    @State private var showItemTypePicker = false
    @State private var pendingNewCategory: ItemCategory?
    @State private var scrolledUnder = false
    /// Bumped when new audit data arrives so the gauge intro replays (see
    /// `WatchtowerIntroGate` — tab switches alone never replay it).
    @State private var refreshCount = 0
    /// Auto-audit runs at most once per screen appearance so revisiting the tab
    /// never re-triggers the engine; reset when the persona changes.
    @State private var didAutoAudit = false
    @State private var paywallContext: LooxPaywallContext?

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

    /// Security only has something to say about credentials: login items (their
    /// password / 2FA / passkey / URL hygiene) and anything else carrying a
    /// password. A vault of only notes, identities, or cards has nothing to
    /// score, so it shows the empty state rather than a misleading 100% ring.
    private var emptyVault: Bool {
        env.repository.activePersonaItems.allSatisfy {
            $0.category != .login && $0.passwordField == nil
        }
    }

    var body: some View {
        @Bindable var uiState = uiState
        return NavigationStack(path: $uiState.watchtowerPath) {
            ZStack(alignment: .top) {
                if emptyVault {
                    // Full-bleed plain-canvas first-run state (its own white background).
                    WatchtowerEmptyStateView(onAdd: { showItemTypePicker = true })
                } else {
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
                }

                // Floating header overlays the scroll content — no title, just the action set.
                VaultScreenHeader {
                    HeaderActionCluster {
                        Button { showItemTypePicker = true } label: {
                            PolarisIcon(Icons.pageAdd, size: Metric.iconUtility)
                                .themedForeground()
                                .frame(width: Metric.hitMin, height: Metric.hitMin)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Add Item"))
                    }
                }
            }
            .environment(\.vaultHeaderScrolledUnder, scrolledUnder)
            .themedWallpaper(env.theme.wallpaper,
                             fallback: Color(rgb: env.theme.active.groupedBackground))
            .platformHiddenNavigationBar()
            .sheet(item: $paywallContext) { context in NavigationStack { LooxPaywallScreen(context: context) } }
            .sheet(item: $editorTarget) { ItemEditorScreen(target: $0) }
            .sheet(isPresented: $showItemTypePicker, onDismiss: {
                if let category = pendingNewCategory {
                    pendingNewCategory = nil
                    editorTarget = .new(category)
                }
            }) {
                ItemTypePickerSheet { pendingNewCategory = $0; showItemTypePicker = false }
            }
            .navigationDestination(for: String.self) { itemID in
                ItemDetailScreen(itemID: itemID).fullScreenPush()
            }
            .navigationDestination(for: WatchtowerCategory.self) { category in
                categoryScreen(for: category).fullScreenPush()
            }
            .task { reload(); autoAuditIfStale(); rescheduleAuditReminder() }
            // Security audits the ACTIVE persona's vault — switching persona reloads.
            .onChange(of: env.repository.activePersona?.id) {
                didAutoAudit = false
                reload()
                autoAuditIfStale()
            }
            .onChange(of: env.repository.items.count) {
                health = PasswordAudit.analyze(env.repository.activePersonaItems)
            }
            // A completed run IS a data moment: refresh the payload + replay intro,
            // then push the next periodic reminder out from this fresh audit.
            .onChange(of: controller.phase) { _, phase in
                if phase == .finished {
                    reload()
                    rescheduleAuditReminder()
                }
            }
            // Unlocking is when the key (and plaintext) becomes available again —
            // the earliest safe moment to auto-run a stale audit.
            .onChange(of: env.session.vaultKey == nil) { _, locked in
                if locked {
                    // Lock mid-run: the plaintext snapshot inside the running task
                    // must not outlive the session — cancel immediately.
                    controller.cancel()
                } else {
                    autoAuditIfStale()
                }
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

    // MARK: - Periodic auto-audit

    /// The audit is stale when the vault has items and either was never audited
    /// or the last audit is older than the reminder cadence.
    private var auditIsStale: Bool {
        guard !emptyVault else { return false }
        guard let completedAt = latestPayload?.completedAt else { return true }
        return Date.now.timeIntervalSince(completedAt) >= AuditReminder.cadence
    }

    /// Run an audit unprompted when the user opens Security and the vault is due,
    /// so the score stays current without them remembering to tap the button.
    /// Guarded to run once per appearance, only while unlocked and idle.
    private func autoAuditIfStale() {
        guard !didAutoAudit,
              env.session.vaultKey != nil,
              controller.phase == .idle,
              auditIsStale else { return }
        didAutoAudit = true
        controller.start(env: env)
    }

    /// After an audit completes, push the local reminder out to the next cadence
    /// window (or clear it if the user turned reminders off).
    private func rescheduleAuditReminder() {
        guard let completedAt = latestPayload?.completedAt else { return }
        AuditReminderNotificationService.shared.reschedule(
            lastAuditedAt: completedAt,
            enabled: env.settings.auditRemindersEnabled)
    }

    // MARK: - Destinations

    /// Compact iOS pushes the category screen onto the UIKit shell (native slide
    /// covering the tab bar); the iPad/Mac sidebar (no navigator) appends to its
    /// own SwiftUI stack path.
    private func openCategory(_ category: WatchtowerCategory) {
        // Paid-surface gate (§5.3): full report, Fix Queue and history are the
        // paid workflow (§3.1). The Free floor never gates — score, strength,
        // audit runs and every finding group (Critical/High visibility with
        // affected items) stay open below.
        if LooxMembership.purchasesEnabled,
           !LooxGate.fullWatchtower(env.entitlements.tier),
           isPaidSurface(category) {
            paywallContext = .watchtower
            return
        }
        if let navigator { navigator.push { categoryScreen(for: category) } }
        else { uiState.watchtowerPath.append(category) }
    }

    private func isPaidSurface(_ category: WatchtowerCategory) -> Bool {
        switch category {
        case .fullReport, .fixQueue, .history, .historyDetail: return true
        case .strength, .audit, .whyScore, .findingGroup: return false
        }
    }

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

    // Hidden entirely when the vault is empty — the empty-state card in
    // `contentSection` owns that surface (no misleading score-0 ring).
    @ViewBuilder
    private var ringSection: some View {
        if !emptyVault {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if let latestPayload {
                        Button { openCategory(.whyScore) } label: {
                            WatchtowerScoreRing(score: latestPayload.score, introKey: introKey)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Vault Health"))
                        .accessibilityHint(Text("Why this score"))
                    } else {
                        // Items exist but no audit has completed yet.
                        WatchtowerPendingRing()
                    }
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
                    } else {
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
    }

    private func lastAuditedText(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        return days == 0
            ? appString("Last audited today")
            : appString("Last audited \(days) days ago")
    }

    // MARK: - Main content

    // Empty vault is handled full-screen at the body level; this is the
    // populated scroll content.
    private var contentSection: some View { populatedContent }

    @ViewBuilder
    private var populatedContent: some View {
        VStack(spacing: Space.s5) {
            // One filled primary; the resume path is the quiet tinted secondary
            // (the style owns typography and height — plain Text labels only).
            Button { openCategory(.audit) } label: {
                HStack(spacing: Space.s2) {
                    PolarisIcon(Icons.shieldPerson, size: Metric.iconInline)
                    Text("Run Vault Audit")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .padding(.horizontal, Space.gutter)

            if let sections, sections.actNowCount > 0 {
                Button { openCategory(.fixQueue) } label: {
                    Text(verbatim: appString("Continue fixing \(sections.actNowCount) issues"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedTinted)
                .padding(.horizontal, Space.gutter)
            }

            Button { openCategory(.strength) } label: {
                WatchtowerStrengthCard(overallStrength: health.overallStrength, introKey: introKey)
            }
            .buttonStyle(PressableSurfaceStyle(theme: env.theme.active,
                                               base: Color(rgb: env.theme.active.elevatedBackground),
                                               cornerRadius: Radius.md))
            .padding(.horizontal, Space.gutter)

            if let sections, !sections.isEmpty {
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
                Button { openCategory(.history) } label: {
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
                                                   cornerRadius: Radius.md))
                .padding(.horizontal, Space.gutter)
            }

            hibpToggleSection
        }
        .padding(.top, Space.s4)
    }

    // MARK: - All clear

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
