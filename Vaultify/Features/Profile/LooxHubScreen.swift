import SwiftUI

/// Loox membership screen (iCloud+ idiom): tier name + member name on the left,
/// the circular member seal on the right, then a live usage grid of everything
/// the membership includes, and the app-wide Approval Mode toggle. Reached from
/// Profile → "Loox".
///
/// The header title is the TIER display name ("Loox" / "Loox+" / "Loox Max"),
/// so the screen doubles as the free hub and the subscriber overview. Usage
/// numbers are device-local, display-only counts (the backend counter becomes
/// the enforcement authority once the entitlement service exists); quota
/// denominators appear only once purchases launch (`LooxMembership`).
struct LooxHubScreen: View {
    @Environment(AppEnvironment.self) private var env
    /// Profile/hub live on a full-screen navigator push COVERING the TabView —
    /// tab-switching actions must pop back to root first or the switch happens
    /// invisibly underneath (see `AppNavigator.push`).
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    @State private var confirmApprovalOff = false
    @State private var showPaywall = false

    private var tier: LooxTier { env.entitlements.tier }
    private var quotas: LooxQuotas { tier.quotas }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                header
                if env.entitlements.purchasesEnabled { planSection }
                if showsQuotas { quotaCard }
                savedSection
                featuresSection
                // Approval Mode stays a control (not a nav tile): app-wide flag,
                // independent of iCloud vault sync (ADR-2).
                ProfileGroupCard { approvalRow }
            }
            .padding(Space.gutter)
            .padding(.bottom, Space.s8)
        }
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        // iCloud+-style: the big title lives in the content header; the nav bar
        // stays an empty inline bar carrying only the back button.
        .navigationTitle("")
        .platformNavigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Turn off Approval Mode?", isPresented: $confirmApprovalOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) {
                env.settings.approvalModeEnabled = false
                Haptics.tap()
            }
        } message: {
            Text("Logins you already shared stay shared. New approval requests and invites pause until you turn this back on.")
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { LooxPaywallScreen(context: .profile) }
        }
    }

    // MARK: Plan (dark until purchases launch — see `LooxMembership`)

    /// Free: one calm upgrade entry (the §5.3 Profile "Gói Loox" discovery
    /// point). Paid: current plan + the management entry. Both land on
    /// `LooxPaywallScreen`, which itself branches on entitlement.
    @ViewBuilder private var planSection: some View {
        ProfileGroupCard {
            if tier == .free {
                Button { showPaywall = true } label: {
                    HStack(spacing: Space.s3) {
                        ProfileRowTile(style: .brandMark)
                        Text("Upgrade to Loox Max").vaultType(.body).themedForeground()
                        Spacer(minLength: Space.s2)
                        PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
                    }
                    .padding(.horizontal, Space.s4)
                    .frame(minHeight: Metric.rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: Space.s3) {
                    ProfileRowTile(style: .brandMark)
                    Text("Your plan").vaultType(.body).themedForeground()
                    Spacer(minLength: Space.s2)
                    Text(verbatim: tier.displayName).vaultType(.subhead).themedForeground(.secondary)
                }
                .padding(.horizontal, Space.s4)
                .frame(minHeight: Metric.rowHeight)
                ProfileRowDivider()
                Button { showPaywall = true } label: {
                    HStack(spacing: Space.s3) {
                        Text("Manage plan").vaultType(.body).themedForeground()
                        Spacer(minLength: Space.s2)
                        PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
                    }
                    .padding(.horizontal, Space.s4)
                    .frame(minHeight: Metric.rowHeight)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Header (tier title + member name | seal)

    private var header: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            VStack(alignment: .leading, spacing: 0) {
                // Bold (not black) at this size, with the badge a step under
                // the cap height — balanced, not shouting (owner 260716).
                LooxTierLabel(tier: tier, badgeHeight: 26, brandWeight: .bold)
                    .vaultType(.largeTitle)
                    .themedForeground()
                Text(verbatim: memberName)
                    .vaultType(.largeTitle)
                    .themedForeground(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
            }
            Spacer(minLength: Space.s3)
            // Subscriber stamp — paid tiers only (owner 260716); Free keeps a
            // clean title-only header.
            if tier > .free {
                LooxMemberSeal(tier: tier)
            }
        }
        .padding(.top, Space.s2)
    }

    /// Identity's Full Name when set, else the active persona's name — the same
    /// resolution `ProfileScreen` uses for the avatar header (kept duplicated:
    /// three lines, and this screen must not grow a dependency on Profile).
    private var memberName: String {
        if let full = env.repository.activeProfileItem?.fields.first(where: { $0.label == "Full Name" })?.value,
           !full.isEmpty {
            return full
        }
        return env.repository.activePersona?.displayName ?? appString("Profile")
    }

    // MARK: Feature grid

    // MARK: Plan limits row (iCloud+ "Storage" row idiom)

    /// White card row summarizing every quota: a thin bar at the HIGHEST
    /// utilization across the countable quotas, pushing the per-quota detail.
    private var quotaCard: some View {
        ProfileGroupCard {
            NavigationLink { LooxQuotaScreen() } label: {
                HStack(spacing: Space.s3) {
                    Text("Plan limits").vaultType(.body).themedForeground()
                    Spacer(minLength: Space.s3)
                    LooxQuotaBar(fraction: maxQuotaFraction)
                        .frame(width: 96)
                    PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
                }
                .padding(.horizontal, Space.s4)
                .frame(minHeight: Metric.rowHeight)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// The most-consumed quota drives the summary bar — "how close am I to
    /// hitting anything" is the question this row answers.
    private var maxQuotaFraction: Double {
        var fractions: [Double] = []
        func add(_ used: Int, _ cap: Int?) {
            if let cap, cap > 0 { fractions.append(Double(used) / Double(cap)) }
        }
        add(retainedAliasCount, quotas.retainedAliases)
        add(linkCreates30d, quotas.linkCreates30d)
        add(quickViewCompletions30d, quotas.quickViewApprovals30d)
        add(outgoingRecipientCount, quotas.outgoingRecipients)
        add(env.repository.personas.count, quotas.personas)
        return fractions.max() ?? 0
    }

    // MARK: "Saved in Loox" (iCloud+ "Saved to iCloud" idiom — vault stats)

    /// White card wrapping a gray tile grid of what the vault holds. Category
    /// tiles jump to Search pre-filled with that category's operator, so the
    /// count expands into the actual list.
    private var savedSection: some View {
        LooxHubSectionCard(title: "Saved in Loox",
                           trailing: "See all",
                           trailingAction: { switchTab(.items) }) {
            categoryTile(.login, tint: SettingsBadgeTint.blue)
            categoryTile(.note, tint: SettingsBadgeTint.orange)
            categoryTile(.identity, tint: SettingsBadgeTint.purple)
            categoryTile(.card, tint: SettingsBadgeTint.green)
            LooxFeatureTile(title: "Passkey", icon: Icons.passkey, tint: SettingsBadgeTint.indigo,
                            metric: appString("\(env.repository.passkeys.count) items"),
                            action: { openSearch(query: "passkey") })
            LooxFeatureTile(title: "Security Score", icon: Icons.watchtower, tint: SettingsBadgeTint.red,
                            metric: securityScoreMetric,
                            action: { switchTab(.watchtower) })
        }
        .task { loadScore() }
    }

    private func categoryTile(_ category: ItemCategory, tint: Color) -> some View {
        LooxFeatureTile(title: category.title, icon: category.iconAsset, tint: tint,
                        metric: appString("\(env.repository.count(forCategory: category)) items"),
                        action: { openSearch(query: searchKeyword(for: category)) })
    }

    /// Canonical search-operator token per category (`SearchOperators` grammar,
    /// matched case- and diacritic-insensitively in both app languages).
    private func searchKeyword(for category: ItemCategory) -> String {
        switch category {
        case .login: "login"
        case .note: "note"
        case .card: "card"
        case .identity: "identity"
        case .sshKey: "ssh"
        case .recoveryCodes: "recovery"
        case .securityQuestions: "security"
        case .custom: "custom"
        }
    }

    /// Hand Search the query, then switch tabs — `SearchScreen.handleEntry`
    /// consumes the entry when the tab lands (the Home "See all" pattern).
    private func openSearch(query: String) {
        env.uiState.searchEntry = .query(query)
        switchTab(.search)
    }

    /// Pop the covering navigator stack, THEN flip the tab — in that order the
    /// TabView is visible again the moment the selection changes.
    private func switchTab(_ tab: VaultTab) {
        navigator?.popToRoot()
        env.uiState.selectedTab = tab
    }

    @State private var securityScore: Int?

    private var securityScoreMetric: String {
        securityScore.map { "\($0)" } ?? appString("Not audited yet")
    }

    private func loadScore() {
        guard let key = env.session.vaultKey else { return }
        let personaID = env.repository.activePersona?.id
        securityScore = AuditReportStore(store: env.store).latest(personaID: personaID, key: key)?.score
    }

    // MARK: Features section (iCloud+ "iCloud+ Features" idiom — tier usage)

    private var featuresSection: some View {
        LooxHubSectionCard(title: featuresTitle) {
            LooxFeatureTile(title: "Private Email", icon: Icons.mail, tint: SettingsBadgeTint.teal,
                            metric: serviceMetric(.privateEmail,
                                                  appString("\(retainedAliasCount) in use")),
                            status: serviceStatus(.privateEmail)) {
                PersonaAliasesScreen()
            }
            LooxFeatureTile(title: "Share Links", icon: Icons.share, tint: SettingsBadgeTint.green,
                            metric: serviceMetric(.shareLink,
                                                  appString("\(linkCreates30d) in 30 days")),
                            status: serviceStatus(.shareLink)) {
                NotificationsScreen()
            }
            // Quick View's user-facing name; its activity shares the
            // notifications surface, so the tile lands there too.
            LooxFeatureTile(title: "Open on Computer", icon: Icons.scanCode, tint: SettingsBadgeTint.indigo,
                            metric: serviceMetric(.quickView,
                                                  appString("\(quickViewCompletions30d) in 30 days")),
                            status: serviceStatus(.quickView)) {
                NotificationsScreen()
            }
            LooxFeatureTile(title: "Sharing", icon: Icons.organization, tint: SettingsBadgeTint.orange,
                            metric: appString("\(outgoingRecipientCount) in use")) {
                FamilyScreen()
            }
            LooxFeatureTile(title: "Profiles", icon: Icons.person, tint: SettingsBadgeTint.blue,
                            metric: appString("\(env.repository.personas.count) in use")) {
                PersonaSwitcherScreen()
            }
            // Watchtower owns its own NavigationStack (it is a tab root), so
            // the tile switches tabs instead of pushing a nested stack.
            LooxFeatureTile(title: "Watchtower", icon: Icons.watchtower, tint: SettingsBadgeTint.green,
                            metric: watchtowerMetric,
                            action: { switchTab(.watchtower) })
        }
        // Screen-open health probe for the connected-service dots — contextual
        // and non-blocking (INV-CAP-02: never at startup, never per-action).
        // Sequential on purpose: the store is MainActor state, and the probes
        // are quick ready-endpoint reads guarded by each service's breaker.
        .task {
            for id in [CapabilityID.privateEmail, .shareLink, .quickView]
            where env.capabilities.userPreference(id) {
                await CapabilityHealthProbe.probe(id, store: env.capabilities)
            }
        }
    }

    /// Tier-aware section title: the paid feature roster belongs to the PLAN
    /// ("Included with Loox Max"), not to the generic brand.
    private var featuresTitle: LocalizedStringResource {
        switch tier {
        case .free: "Included with Loox"
        case .plus: "Included with Loox+"
        case .max: "Included with Loox Max"
        }
    }

    // MARK: Connected-service presentation (dot + off-state metric)

    private func serviceStatus(_ id: CapabilityID) -> CapabilityDisplayStatus {
        CapabilityDisplayStatus.resolve(id, store: env.capabilities)
    }

    /// Preference off ("ẩn tất cả liên quan"): every other surface hides, but the
    /// membership overview keeps the tile with a gray dot and an explicit
    /// "Off in Settings" line — a paying subscriber must be able to see WHERE
    /// the feature went, or the hidden state reads as a broken plan.
    private func serviceMetric(_ id: CapabilityID, _ liveMetric: String) -> String {
        env.capabilities.userPreference(id) ? liveMetric : appString("Off in Settings")
    }

    // MARK: Live usage counts (device-local, display-only)

    private static let rolling30d: TimeInterval = 30 * 24 * 3600

    /// Retained = active or paused; permanently deleted aliases free the slot.
    private var retainedAliasCount: Int {
        env.repository.aliases.filter { $0.status == .active || $0.status == .paused }.count
    }

    private var linkCreates30d: Int {
        let cutoff = Date.now.addingTimeInterval(-Self.rolling30d)
        return env.looxLinks.records.records.filter { $0.createdAt >= cutoff }.count
    }

    private var quickViewCompletions30d: Int {
        let cutoff = Date.now.addingTimeInterval(-Self.rolling30d)
        return env.quickViewHistory.rows.filter { $0.result == .completed && $0.timestamp >= cutoff }.count
    }

    /// Distinct people with an ACTIVE outgoing share — more items to the same
    /// person never consume another seat.
    private var outgoingRecipientCount: Int {
        Set(env.sharingStore.shares.filter { $0.status == .active }.map(\.recipientLabel)).count
    }

    // MARK: Metric copy

    /// Quota denominators render once purchases launch — showing one while
    /// nothing enforces it would lie. In DEBUG an active tier override also
    /// reveals them, so the full tier UI is testable before ASC exists.
    private var showsQuotas: Bool {
        if env.entitlements.purchasesEnabled { return true }
        #if DEBUG
        return env.entitlements.debugTierOverride != nil
        #else
        return false
        #endif
    }

    private var watchtowerMetric: String {
        (!showsQuotas || quotas.fullWatchtower)
            ? appString("Full protection")
            : appString("Essentials")
    }

    // MARK: Section chrome (white card wrapping a gray tile grid)

    /// iCloud+ section idiom: an elevated WHITE card that carries its own
    /// header row (title + optional trailing action) and a two-column grid of
    /// gray tiles inside — the tiles' fixed systemGray6 fill reads against the
    /// card, not the screen background.
    private struct LooxHubSectionCard<Tiles: View>: View {
        @Environment(AppEnvironment.self) private var env
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        let title: LocalizedStringResource
        var trailing: LocalizedStringResource? = nil
        var trailingAction: (() -> Void)? = nil
        @ViewBuilder let tiles: Tiles

        /// Compact keeps the approved two-up iPhone grid — an adaptive minimum
        /// sized for iPad collapsed to ONE stacked column on phone widths.
        /// Regular stays adaptive (3-4 across a wide detail pane).
        private var columns: [GridItem] {
            horizontalSizeClass == .regular
                ? [GridItem(.adaptive(minimum: 200, maximum: 400), spacing: Space.s3)]
                : [GridItem(.flexible(), spacing: Space.s3), GridItem(.flexible())]
        }

        var body: some View {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text(title).vaultType(.headline).themedForeground()
                    Spacer(minLength: Space.s2)
                    if let trailing, let trailingAction {
                        Button(action: trailingAction) {
                            HStack(spacing: Space.s1) {
                                Text(trailing).vaultType(.subhead)
                                PolarisIcon(Icons.chevronRight, size: 12)
                            }
                            .themedForeground(.secondary)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                LazyVGrid(columns: columns, spacing: Space.s3) {
                    tiles
                }
            }
            .padding(Space.s4)
            .background(Color(rgb: env.theme.active.elevatedBackground))
            .vaultCornerRadius(Radius.lg)
            .elevation(.level1)
        }
    }

    // MARK: Approval Mode

    /// Approval Mode — bound to the SAME `approvalModeEnabled` flag as Settings (single source
    /// of truth). Turning OFF asks for confirmation, matching the Settings behavior.
    private var approvalRow: some View {
        Toggle(isOn: Binding(
            get: { env.settings.approvalModeEnabled },
            set: { on in
                if on { env.settings.approvalModeEnabled = true } else { confirmApprovalOff = true }
            }
        )) {
            HStack(spacing: Space.s3) {
                ProfileRowTile(icon: Icons.shieldPerson)
                Text("Approval Mode").vaultType(.body).themedForeground()
            }
        }
        .tint(Color(rgb: env.theme.active.switchOn))
        .toggleStyle(.switch)
        .padding(.horizontal, Space.s4)
        .frame(minHeight: Metric.rowHeight)
    }
}
