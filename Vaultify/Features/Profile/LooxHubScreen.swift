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
                Text(verbatim: tier.displayName)
                    .vaultType(.largeTitle)
                    .themedForeground()
                Text(verbatim: memberName)
                    .vaultType(.largeTitle)
                    .themedForeground(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.65)
            }
            Spacer(minLength: Space.s3)
            LooxMemberSeal(tier: tier)
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
                                metric: usageMetric(retainedAliasCount, of: quotas.retainedAliases)) {
                    PersonaAliasesScreen()
                }
                LooxFeatureTile(title: "Share Links", icon: Icons.share,
                                metric: rollingMetric(linkCreates30d, of: quotas.linkCreates30d)) {
                    NotificationsScreen()
                }
                // Quick View's user-facing name; its activity shares the
                // notifications surface, so the tile lands there too.
                LooxFeatureTile(title: "Open on Computer", icon: Icons.scanCode,
                                metric: rollingMetric(quickViewCompletions30d, of: quotas.quickViewApprovals30d)) {
                    NotificationsScreen()
                }
                LooxFeatureTile(title: "Profiles", icon: Icons.person,
                                metric: usageMetric(env.repository.personas.count, of: quotas.personas)) {
                    PersonaSwitcherScreen()
                }
                LooxFeatureTile(title: "Sharing", icon: Icons.organization,
                                metric: usageMetric(outgoingRecipientCount, of: quotas.outgoingRecipients)) {
                    FamilyScreen()
                }
                // Watchtower owns its own NavigationStack (it is a tab root), so
                // the tile switches tabs instead of pushing a nested stack.
                LooxFeatureTile(title: "Watchtower", icon: Icons.watchtower,
                                metric: watchtowerMetric,
                                action: { env.uiState.selectedTab = .watchtower })
            }
        }
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

    /// "3 of 10 in use" with quotas visible; a plain "3 in use" before that.
    private func usageMetric(_ used: Int, of cap: Int?) -> String {
        if showsQuotas, let cap {
            return appString("\(used) of \(cap) in use")
        }
        return appString("\(used) in use")
    }

    private func rollingMetric(_ used: Int, of cap: Int) -> String {
        if showsQuotas {
            return appString("\(used) of \(cap) in 30 days")
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
