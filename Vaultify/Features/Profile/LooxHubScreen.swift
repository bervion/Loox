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
    @State private var confirmApprovalOff = false
    @State private var showPaywall = false

    private var tier: LooxTier { env.entitlements.tier }
    private var quotas: LooxQuotas { tier.quotas }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s6) {
                header
                if env.entitlements.purchasesEnabled { planSection }
                featureGrid
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

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Included with Loox")
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s3), GridItem(.flexible())],
                      spacing: Space.s3) {
                LooxFeatureTile(title: "Private Email", icon: Icons.mail,
                                metric: serviceMetric(.privateEmail,
                                                      usageMetric(retainedAliasCount, of: quotas.retainedAliases)),
                                progress: serviceProgress(.privateEmail, retainedAliasCount, of: quotas.retainedAliases),
                                status: serviceStatus(.privateEmail)) {
                    PersonaAliasesScreen()
                }
                LooxFeatureTile(title: "Share Links", icon: Icons.share,
                                metric: serviceMetric(.shareLink,
                                                      rollingMetric(linkCreates30d, of: quotas.linkCreates30d)),
                                progress: serviceProgress(.shareLink, linkCreates30d, of: quotas.linkCreates30d),
                                status: serviceStatus(.shareLink)) {
                    NotificationsScreen()
                }
                // Quick View's user-facing name; its activity shares the
                // notifications surface, so the tile lands there too.
                LooxFeatureTile(title: "Open on Computer", icon: Icons.scanCode,
                                metric: serviceMetric(.quickView,
                                                      rollingMetric(quickViewCompletions30d, of: quotas.quickViewApprovals30d)),
                                progress: serviceProgress(.quickView, quickViewCompletions30d, of: quotas.quickViewApprovals30d),
                                status: serviceStatus(.quickView)) {
                    NotificationsScreen()
                }
                LooxFeatureTile(title: "Profiles", icon: Icons.person,
                                metric: usageMetric(env.repository.personas.count, of: quotas.personas),
                                progress: quotaFraction(env.repository.personas.count, of: quotas.personas)) {
                    PersonaSwitcherScreen()
                }
                LooxFeatureTile(title: "Sharing", icon: Icons.organization,
                                metric: usageMetric(outgoingRecipientCount, of: quotas.outgoingRecipients),
                                progress: quotaFraction(outgoingRecipientCount, of: quotas.outgoingRecipients)) {
                    FamilyScreen()
                }
                // Watchtower owns its own NavigationStack (it is a tab root), so
                // the tile switches tabs instead of pushing a nested stack.
                LooxFeatureTile(title: "Watchtower", icon: Icons.watchtower,
                                metric: watchtowerMetric,
                                action: { env.uiState.selectedTab = .watchtower })
            }
            if showsQuotas {
                Text("Share Links and Open on Computer count the last 30 days.")
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
                    .padding(.top, Space.s1)
            }
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

    private func serviceProgress(_ id: CapabilityID, _ used: Int, of cap: Int?) -> Double? {
        guard env.capabilities.userPreference(id) else { return nil }
        return quotaFraction(used, of: cap)
    }

    /// Quota fraction for the thin tile bar — only once quotas are real
    /// (`showsQuotas`), and never for uncapped (nil) quotas.
    private func quotaFraction(_ used: Int, of cap: Int?) -> Double? {
        guard showsQuotas, let cap, cap > 0 else { return nil }
        return Double(used) / Double(cap)
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

    /// Compact "3/10" with quotas visible (the tile's progress bar and title
    /// carry the meaning; spelled-out copy truncated on small iPhones); a plain
    /// "3 in use" before quotas launch.
    private func usageMetric(_ used: Int, of cap: Int?) -> String {
        if showsQuotas, let cap {
            return "\(used)/\(cap)"
        }
        return appString("\(used) in use")
    }

    private func rollingMetric(_ used: Int, of cap: Int) -> String {
        if showsQuotas {
            return "\(used)/\(cap)"
        }
        return appString("\(used) in 30 days")
    }

    private var watchtowerMetric: String {
        (!showsQuotas || quotas.fullWatchtower)
            ? appString("Full protection")
            : appString("Essentials")
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
