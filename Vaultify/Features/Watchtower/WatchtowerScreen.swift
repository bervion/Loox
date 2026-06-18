import SwiftUI

/// Typed navigation values for the "To fix" drill-down categories.
/// Declared at file scope (not private) so NavigationLink can infer the type.
enum WatchtowerCategory: Hashable {
    case compromised, reused, weak, missing2FA
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

    @State private var health = VaultHealth.empty
    @State private var pwned: [VaultIssue] = []
    @State private var checking = false
    @State private var editorTarget: EditorTarget?
    @State private var scrolledUnder = false

    private var allClear: Bool {
        health.analyzedCount > 0 && totalIssueCount == 0
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
        NavigationStack {
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
                .refreshable { await fullAudit() }

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
                        .frame(width: Metric.hitMin, height: Metric.hitMin)
                        .accessibilityLabel(Text("Add Item"))
                    }
                }
            }
            .environment(\.vaultHeaderScrolledUnder, scrolledUnder)
            .themedWallpaper(env.theme.wallpaper,
                             fallback: Color(rgb: env.theme.active.groupedBackground))
            .toolbar(.hidden, for: .navigationBar)
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
            .onChange(of: env.repository.items.count) {
                health = PasswordAudit.analyze(env.repository.items)
            }
        }
    }

    // MARK: - Category screen factory

    @ViewBuilder
    private func categoryScreen(for category: WatchtowerCategory) -> some View {
        switch category {
        case .compromised:
            WatchtowerCategoryScreen(title: "Exposed password", issues: pwned)
        case .reused:
            WatchtowerCategoryScreen(title: "Reused passwords", issues: health.reused)
        case .weak:
            WatchtowerCategoryScreen(title: "Weak passwords", issues: health.weak)
        case .missing2FA:
            WatchtowerCategoryScreen(title: "Set up two-factor authentication", issues: health.missing2FA)
        }
    }

    // MARK: - Score ring + subtitle

    private var ringSection: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                WatchtowerScoreRing(score: health.score)
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
            WatchtowerStrengthCard(overallStrength: health.overallStrength) {
                // Tapping strength card navigates to weak-password drill-down
                // when there are weak items; otherwise it's informational.
            }
            .padding(.horizontal, Space.gutter)

            if allClear {
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
                ) {}
            }
            .buttonStyle(.plain)

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

    // MARK: - All-clear

    private var allClearView: some View {
        HStack(spacing: Space.s3) {
            PolarisIcon(Icons.checkCircle, size: Metric.iconInline)
                .themedForeground(.success)
            Text("Every password is strong and unique.")
                .vaultType(.callout)
                .themedForeground(.secondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
        .padding(.horizontal, Space.gutter)
    }

    // MARK: - HIBP toggle

    private var hibpToggleSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Toggle(isOn: hibpBinding) {
                Text("Check for known breaches")
            }
            .toggleStyle(.themed)

            Text("Uses k-anonymity — only the first five characters of each password's SHA-1 hash are sent. Passwords never leave your device.")
                .vaultType(.footnote)
                .themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .themedCard()
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
        health = PasswordAudit.analyze(env.repository.items)
        if env.settings.hibpEnabled { await runHIBP() }
    }

    private func runHIBP() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        var cache: [String: Int] = [:]
        var results: [VaultIssue] = []
        for item in env.repository.items {
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
                                                   detail: "Seen \(count) times in breaches"))
            }
        }
        pwned = results
    }
}
