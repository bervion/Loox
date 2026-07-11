import SwiftUI

/// Typed navigation values for the Watchtower drill-downs.
/// Declared at file scope (not private) so NavigationLink can infer the type.
enum WatchtowerCategory: Hashable {
    case compromised, reused, weak, missing2FA
    /// The "Overall password strength" card → per-item strength breakdown.
    case strength
}

/// Watchtower — vault health monitor.
///
/// Layout (per DS Watchtower.jsx):
///   Title "Watchtower"
///   → WatchtowerScoreRing (270° speedometer, hero element)
///   → Subtitle "Fix N issues below…"
///   → WatchtowerStrengthCard  ┐ revealed ~0.3 s after ring sweep starts
///   → "To fix" section        ┘ so the ring animates as the hero moment
///   → HIBP toggle (bottom)
///   → All-clear state when issueCount == 0
struct WatchtowerScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(UIStateStore.self) private var uiState

    @State private var health = VaultHealth.empty
    @State private var pwned: [VaultIssue] = []
    @State private var checking = false
    @State private var editorTarget: EditorTarget?
    @State private var scrolledUnder = false
    /// Bumped by pull-to-refresh so the gauge/bar intro replays (see
    /// `WatchtowerIntroGate` — tab switches alone never replay it).
    @State private var refreshCount = 0

    /// Data-context identity for the intro animations: persona switch or an
    /// explicit refresh changes it; a mere tab revisit does not.
    private var introKey: String {
        "\(env.repository.activePersona?.id ?? "-")|\(refreshCount)"
    }

    private var allClear: Bool {
        health.analyzedCount > 0 && totalIssueCount == 0
    }

    /// Nothing to analyze yet (no items with a password, no 2FA-capable logins). Distinct
    /// from `allClear`: without this the "To fix" card rendered with zero rows — a hollow
    /// scaffold with a header and no content.
    private var emptyVault: Bool {
        health.analyzedCount == 0 && totalIssueCount == 0
    }

    private var totalIssueCount: Int {
        health.weak.count + health.reused.count + pwned.count + health.missing2FA.count
    }

    private var hibpBinding: Binding<Bool> {
        Binding(
            get: { env.settings.hibpEnabled },
            set: { isOn in
                env.settings.hibpEnabled = isOn
                if isOn { Task { await runHIBP() } } else { pwned = [] }
            })
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
                .refreshable {
                    refreshCount += 1   // an explicit reload IS an intro moment
                    await fullAudit()
                }

                // Floating header overlays the scroll content — glass blurs beneath.
                VaultScreenHeader("Watchtower") {
                    HeaderActionCluster {
                        // Add — menu to choose item type to create
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
                        // Plain glyph menu — macOS would otherwise draw a bordered pull-down button.
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
            // Item detail navigation (tapping a row in WatchtowerCategoryScreen)
            .navigationDestination(for: String.self) { itemID in
                ItemDetailScreen(itemID: itemID)
            }
            // Category drill-down navigation
            .navigationDestination(for: WatchtowerCategory.self) { category in
                categoryScreen(for: category)
            }
            .overlay { if checking { checkingOverlay } }
            .task { await fullAudit() }
            // Watchtower audits the ACTIVE persona's vault — switching persona
            // re-audits (and the introKey change replays the gauge intro).
            .onChange(of: env.repository.activePersona?.id) {
                Task { await fullAudit() }
            }
            .onChange(of: env.repository.items.count) {
                health = PasswordAudit.analyze(env.repository.activePersonaItems)
            }
        }
    }

    // MARK: - Category screen factory

    @ViewBuilder
    private func categoryScreen(for category: WatchtowerCategory) -> some View {
        switch category {
        case .compromised:
            WatchtowerCategoryScreen(
                title: "Exposed password", issues: pwned,
                infoNote: "Uses k-anonymity. Only the first five characters of each password's SHA-1 hash are sent. Passwords never leave your device.")
        case .reused:
            WatchtowerCategoryScreen(title: "Reused passwords", issues: health.reused)
        case .weak:
            WatchtowerCategoryScreen(title: "Weak passwords", issues: health.weak)
        case .missing2FA:
            WatchtowerCategoryScreen(title: "Set up two-factor authentication", issues: health.missing2FA)
        case .strength:
            WatchtowerStrengthScreen()
        }
    }

    // MARK: - Score ring + subtitle

    private var ringSection: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                WatchtowerScoreRing(score: health.score, introKey: introKey)
                Spacer()
            }
            .padding(.vertical, Space.s2)

            if totalIssueCount > 0 {
                Text("Fix \(totalIssueCount) issues below to raise your vault's security score.")
                    .vaultType(.callout)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Space.s7)
                    .padding(.bottom, Space.s3)
            }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var contentSection: some View {
        // Shown immediately alongside the ring; the strength bar runs its own
        // grow-in animation (see WatchtowerStrengthBar) so it animates in sync.
        VStack(spacing: Space.s5) {
            NavigationLink(value: WatchtowerCategory.strength) {
                WatchtowerStrengthCard(overallStrength: health.overallStrength, introKey: introKey)
            }
            .buttonStyle(PressableSurfaceStyle(theme: env.theme.active,
                                               base: Color(rgb: env.theme.active.elevatedBackground),
                                               cornerRadius: Radius.lg, bordered: true))
            .padding(.horizontal, Space.gutter)

            if emptyVault {
                emptyVaultView
            } else if allClear {
                allClearView
            } else {
                issueSection
            }

            hibpToggleSection
        }
        .padding(.top, Space.s4)
    }

    // MARK: - "To fix" issue list

    @ViewBuilder
    private var issueSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("To fix")
                .vaultType(.sectionLabel)
                .themedForeground(.secondary)
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, Space.s1)

            ThemedCard(cornerRadius: Radius.lg, padding: 0) {
                VStack(spacing: 0) {
                    categoryRowList
                }
            }
            .padding(.horizontal, Space.gutter)
        }
    }

    @ViewBuilder
    private var categoryRowList: some View {
        let entries = activeCategoryEntries
        ForEach(entries) { entry in
            NavigationLink(value: entry.category) {
                CategoryRow(
                    icon: entry.icon,
                    tintRole: entry.tintRole,
                    title: entry.title,
                    subtitle: entry.subtitle,
                    count: entry.count
                )
            }
            .buttonStyle(PressableSurfaceStyle(theme: env.theme.active))

            // Divider after every entry except the last
            if entry.id != entries.last?.id {
                ThemedDivider()
                    .padding(.leading, Space.gutter + Metric.iconTile + Space.s3)
            }
        }
    }

    // Build the ordered list of non-zero issue categories
    private struct CategoryEntry: Identifiable {
        var id: WatchtowerCategory { category }
        let category: WatchtowerCategory
        let icon: String
        let tintRole: ThemeRole
        let title: LocalizedStringResource
        let subtitle: String
        let count: Int
    }

    private var activeCategoryEntries: [CategoryEntry] {
        var entries: [CategoryEntry] = []
        if !pwned.isEmpty {
            entries.append(CategoryEntry(
                category: .compromised,
                icon: Icons.shieldAlert,
                tintRole: .destructive,
                title: "Exposed password",
                subtitle: appString("\(pwned.count) in a data breach"),
                count: pwned.count))
        }
        if !health.reused.isEmpty {
            entries.append(CategoryEntry(
                category: .reused,
                icon: Icons.copy,
                tintRole: .warning,
                title: "Reused passwords",
                subtitle: appString("\(health.reused.count) share a password"),
                count: health.reused.count))
        }
        if !health.weak.isEmpty {
            entries.append(CategoryEntry(
                category: .weak,
                icon: Icons.lock,
                tintRole: .warning,
                title: "Weak passwords",
                subtitle: appString("\(health.weak.count) easy to guess"),
                count: health.weak.count))
        }
        if !health.missing2FA.isEmpty {
            entries.append(CategoryEntry(
                category: .missing2FA,
                icon: Icons.checkCircle,
                tintRole: .accent,
                title: "Set up two-factor authentication",
                subtitle: appString("\(health.missing2FA.count) can use 2FA"),
                count: health.missing2FA.count))
        }
        return entries
    }

    // MARK: - Empty vault

    private var emptyVaultView: some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(Icons.shield, size: Metric.iconInline)
                .themedForeground(.secondary)
            Text("Add a password to see your vault's security score.")
                .vaultType(.callout)
                .themedForeground(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()   // themedCard already pads Space.s4 — no extra padding
        .padding(.horizontal, Space.gutter)
    }

    // MARK: - All-clear

    private var allClearView: some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(Icons.checkCircle, size: Metric.iconInline)
                .themedForeground(.success)
            Text("Every password is strong and unique.")
                .vaultType(.callout)
                .themedForeground(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()   // themedCard already pads Space.s4 — no extra padding
        .padding(.horizontal, Space.gutter)
    }

    // MARK: - HIBP toggle

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
        .themedCard()   // themedCard already pads Space.s4 — no extra padding
        .padding(.horizontal, Space.gutter)
    }

    // MARK: - Checking overlay

    private var checkingOverlay: some View {
        ProgressView("Checking breaches…")
            .padding(Space.s5)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Audit logic

    private func fullAudit() async {
        health = PasswordAudit.analyze(env.repository.activePersonaItems)
        if env.settings.hibpEnabled { await runHIBP() }
    }

    private func runHIBP() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        var cache: [String: Int] = [:]
        var results: [VaultIssue] = []
        for item in env.repository.activePersonaItems {
            guard let password = item.passwordField?.value, !password.isEmpty else { continue }
            let count: Int
            if let cached = cache[password] {
                count = cached
            } else {
                count = await HIBPService.pwnedCount(password: password)
                cache[password] = count
            }
            if count > 0 {
                results.append(PasswordAudit.issue(item, kind: .pwned,
                                                   detail: appString("Seen \(count) times in breaches")))
            }
        }
        pwned = results
    }
}
