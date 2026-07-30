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

    private func startTourIfScoreIsShowing() {
        guard !emptyVault, latestPayload != nil else { return }
        env.tutorial.startIfNeeded(.watchtower)
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

    private var dismissedFingerprints: Set<String> {
        guard let key = env.session.vaultKey else { return [] }
        let reportStore = AuditReportStore(store: env.store)
        if let report = controller.lastRun {
            return reportStore.hiddenFingerprints(for: report.findings,
                                                  personaID: personaID, key: key)
        }
        if let latestPayload {
            return reportStore.hiddenFingerprints(
                fingerprints: latestPayload.findings.map { ($0.fingerprint, $0.ruleID) },
                ruleVersions: latestPayload.ruleVersions,
                personaID: personaID, key: key)
        }
        return []
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
                .refreshable { reload(replayIntro: true) }
                }

                // Floating header overlays the scroll content — no title, just the action set.
                VaultScreenHeader {
                    HeaderActionCluster {
                        Button { showItemTypePicker = true } label: {
                            VaultIcon(Icons.pageAdd, size: Metric.iconUtility)
                                .themedForeground()
                                .frame(width: Metric.hitMin, height: Metric.hitMin)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Add Item"))

                        // Run Vault Audit lives in the header's glass capsule
                        // (rightmost — the tab's primary verb), not as a filled
                        // bar pushing the content down. Icon-rank primary, like
                        // every other chrome control.
                        Button { openCategory(.audit) } label: {
                            VaultIcon(Icons.shieldPerson, size: Metric.iconUtility)
                                .themedForeground()
                                .frame(width: Metric.hitMin, height: Metric.hitMin)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Run Vault Audit"))
                        .tutorialAnchor(TutorialAnchorID.watchtowerRunAudit)
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
            .task {
                reload(); autoAuditIfStale(); rescheduleAuditReminder()
                startTourIfScoreIsShowing()
            }
            .analyticsScreen("watchtower")
            // A tour asked for but not yet shown must not pop over another tab.
            .onDisappear { env.tutorial.cancelPendingStart() }
            // Security audits the ACTIVE persona's vault — switching persona reloads.
            .onChange(of: env.repository.activePersona?.id) {
                didAutoAudit = false
                reload()
                autoAuditIfStale()
            }
            // A first audit can land after this screen appeared, so the tour
            // also arms when the score arrives — it explains that number, and
            // pointing at a ring that says "not checked yet" explains nothing.
            .onChange(of: latestPayload?.score) { startTourIfScoreIsShowing() }
            .onChange(of: env.repository.items.count) {
                health = PasswordAudit.analyze(env.repository.activePersonaItems)
            }
            // A completed run IS a data moment: refresh the payload + replay intro,
            // then push the next periodic reminder out from this fresh audit.
            .onChange(of: controller.phase) { _, phase in
                if phase == .finished {
                    reload(replayIntro: true)
                    rescheduleAuditReminder(allowPermissionPrompt: true)
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

    /// Refresh health + the saved report. `replayIntro` bumps the intro key so the
    /// gauge/bar choreography replays — ONLY for real data moments (pull to
    /// refresh, a finished audit). `.task` runs on every tab visit, and bumping
    /// there made the intro restart on every switch, which is exactly what the
    /// once-per-key gate exists to prevent (and rapid restarts are what exposed
    /// the bar's overflow).
    private func reload(replayIntro: Bool = false) {
        health = PasswordAudit.analyze(env.repository.activePersonaItems)
        if let key = env.session.vaultKey {
            latestPayload = AuditReportStore(store: env.store).latest(personaID: personaID, key: key)
        }
        if replayIntro { refreshCount += 1 }
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
    /// window (or clear it if the user turned reminders off). The permission
    /// prompt is allowed only right after a completed audit — a deliberate user
    /// action, and a contextual moment to ask ("remind you next time?"). A tab
    /// visit never prompts: that dialog used to land on top of this tab's tour.
    private func rescheduleAuditReminder(allowPermissionPrompt: Bool = false) {
        guard let completedAt = latestPayload?.completedAt else { return }
        AuditReminderNotificationService.shared.reschedule(
            lastAuditedAt: completedAt,
            enabled: env.settings.auditRemindersEnabled,
            allowPermissionPrompt: allowPermissionPrompt)
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
        if env.entitlements.purchasesEnabled,
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
            VaultAuditFlowScreen(controller: controller, openCategory: openCategory)
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

                if latestPayload == nil {
                    Text("Run your first audit to see your vault's health score.")
                        .vaultType(.callout)
                        .themedForeground(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Space.s7)
                        .padding(.bottom, Space.s3)
                }
                // Audited meta (last audited / item count) folded into the
                // description paragraph below — see `scoreDescription`.
            }
            // The tour spotlights the WHOLE ring block, not a circle cut tight
            // around the dial — the step is about this surface, and the rounded
            // window reads as "this card" instead of a keyhole.
            .tutorialAnchor(TutorialAnchorID.watchtowerScore)
        }
    }

    private func lastAuditedText(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0
        return days == 0
            ? appString("Last audited today")
            : appString("Last audited \(days) days ago")
    }

    /// The paragraph under the ring: meaning → action → audit meta, as full
    /// localized sentences joined into running text.
    private var scoreDescription: String {
        var sentences = [
            appString("Your score is an overall read of how safe your vault is, based on password strength, reuse, known leaks, and two-factor coverage."),
            appString("Fix the flagged items below to raise it."),
        ]
        if let latestPayload {
            sentences.append(lastAuditedText(latestPayload.completedAt) + ".")
            if latestPayload.confidenceLimited {
                sentences.append(appString("Based on \(latestPayload.analyzedItemCount) items") + ".")
            }
        }
        return sentences.joined(separator: " ")
    }

    // MARK: - Main content

    // Empty vault is handled full-screen at the body level; this is the
    // populated scroll content.
    private var contentSection: some View { populatedContent }

    @ViewBuilder
    private var populatedContent: some View {
        VStack(spacing: Space.s5) {
            // Compact grey chip under the ring (1P's "Share My Score" spot):
            // warning glyph + a short verb. Run Vault Audit moved to the header
            // capsule, so this is the section's only button.
            if let sections, sections.actNowCount > 0 {
                Button { openCategory(.fixQueue) } label: {
                    HStack(spacing: Space.s2) {
                        VaultIcon(Icons.alert, size: Metric.iconCompact)
                            .themedForeground(.warning)
                        Text("Fix issues")
                            .vaultType(.subhead).fontWeight(.semibold)
                            .themedForeground(.primary)
                        VaultCountBadge(count: sections.actNowCount,
                                        tint: env.theme.active.color(.warning))
                    }
                    .padding(.horizontal, Space.s4)
                    .frame(minHeight: Metric.controlMedium)
                    .background(Color(rgb: env.theme.active.controlBackground),
                                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(verbatim: appString("Continue fixing \(sections.actNowCount) issues")))
            }

            // What the score means, in one left-aligned paragraph (1P register):
            // the meaning, the action, and the audit meta in running text instead
            // of centered caption fragments under the ring.
            if latestPayload != nil {
                Text(verbatim: scoreDescription)
                    .vaultType(.callout)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.gutter)
            }

            Button { openCategory(.strength) } label: {
                WatchtowerStrengthCard(overallStrength: health.overallStrength,
                                       grades: health.grades, introKey: introKey)
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
                        VaultIcon(Icons.clock, size: Metric.iconInline)
                            .themedForeground(.secondary)
                        Text("Audit history")
                            .vaultType(.body)
                            .themedForeground(.primary)
                        Spacer()
                        VaultIcon(Icons.chevronRight, size: 14)
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
            VaultIcon(Icons.checkCircle, size: Metric.iconInline)
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
