import SwiftUI

/// Home tab — DS-spec composition (Phase 5):
/// Header → Search entry → Quick actions → TOTP scroller → Needs Attention →
/// Favorites → All items → Empty state when vault is empty.
///
/// `selectedFolderId` nil = "All Spaces" (no folder filter). Every section is
/// filtered by the selected folder and renders only when non-empty.
struct HomeScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var path = NavigationPath()
    @State private var editorTarget: EditorTarget?
    @State private var showSettings = false
    @State private var showGenerator = false
    @State private var showTotpList = false
    @State private var selectedFolderId: String?
    @State private var sortOrder: VaultSort = .updated
    @State private var scrolledUnder = false
    /// Cached Watchtower issue count for the quick-action badge (recomputed on appear and
    /// when the item set changes — `PasswordAudit.analyze` is too costly to run per render).
    @State private var watchtowerIssueCount = 0

    // MARK: Filtered sections (recomputed when items or folder changes)

    private var totpItems: [VaultItem] {
        env.repository.totpItems(folder: selectedFolderId)
    }

    private var attentionItems: [VaultItem] {
        env.repository.itemsNeedingAttention(folder: selectedFolderId, limit: 4)
    }

    private var favoriteItems: [VaultItem] {
        env.repository.favorites(folder: selectedFolderId)
    }

    private var allItems: [VaultItem] {
        let sorted = sortOrder.apply(env.repository.allItems(folder: selectedFolderId))
        // Pinned items float to the top, keeping the chosen sort within each group.
        return sorted.filter(\.pinned) + sorted.filter { !$0.pinned }
    }

    /// Whole-vault security issues (weak + reused + missing 2FA) for the Watchtower badge —
    /// matches the Watchtower screen's synchronous count (HIBP/pwned excluded; that needs the
    /// network). Not folder-scoped: Watchtower audits the entire vault.
    private func recomputeWatchtowerCount() {
        let health = PasswordAudit.analyze(env.repository.items)
        watchtowerIssueCount = health.weak.count + health.reused.count + health.missing2FA.count
    }

    var body: some View {
        NavigationStack(path: $path) {
            // ZStack lets the header float over scroll content so glass blurs it.
            ZStack(alignment: .top) {
                Group {
                    if env.repository.items.isEmpty {
                        emptyVaultState
                    } else {
                        scrollContent
                    }
                }

                // Header overlays the scroll content — glass blurs whatever scrolls beneath.
                HomeHeaderBar(
                    selectedFolderId: $selectedFolderId,
                    onAddCategory: { editorTarget = .new($0) },
                    onSettings: { showSettings = true }
                )
            }
            .environment(\.vaultHeaderScrolledUnder, scrolledUnder)
            .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .vaultNavigationDestinations()
            .task { recomputeWatchtowerCount() }
            .onChange(of: env.repository.items.count) { recomputeWatchtowerCount() }
            // New items inherit the Space currently selected on Home (nil = All Spaces →
            // editor falls back to the primary Space).
            .sheet(item: $editorTarget) { ItemEditorScreen(target: $0, preselectedFolderId: selectedFolderId) }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .sheet(isPresented: $showGenerator) { GeneratorScreen() }
        }
    }

    // MARK: Main scrollable content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Top inset clears the floating header bar + reports scroll-edge state so
                // the header blur reveals only once content scrolls beneath it.
                VaultHeaderScrollSpacer(scrolledUnder: $scrolledUnder)

                VStack(alignment: .leading, spacing: Space.s6) {
                    // 3. Quick actions grid (Reminders-style colour cards)
                    quickActionsGrid

                    // 4. TOTP scroller (only when items with TOTP exist)
                    if !totpItems.isEmpty {
                        totpSection
                    }

                    // 5. Needs attention (max 4)
                    if !attentionItems.isEmpty {
                        attentionSection
                    }

                    // 6. Favorites
                    if !favoriteItems.isEmpty {
                        favoritesSection
                    }

                    // 7. All items (pinned first)
                    allItemsSection
                }
                .padding(.horizontal, Space.gutter)
                // Bottom inset so the floating tab bar never obscures the last row.
                .padding(.bottom, TabBarMetric.contentBottomInset)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Quick actions

    /// Reminders-style quick-action cards in a 2-up grid: Add · Generate (top row),
    /// 2FA · Watchtower (bottom row). 2FA and Watchtower carry a live count badge.
    private var quickActionsGrid: some View {
        // One GlassEffectContainer for all 8 glass views (4 cards + 4 badges) → a single
        // backdrop layer; fixes the per-frame glass-update warning on theme changes.
        VaultGlassGroup {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Space.s3),
                      GridItem(.flexible(), spacing: Space.s3)],
            spacing: Space.s3
        ) {
            // Add — presents the item-type menu (uses ic_page_add, matches the header).
            Menu {
                newItemMenuItems
            } label: {
                QuickActionCardLabel(
                    icon: Icons.pageAdd,
                    label: LocalizedStringResource("Add Item").inAppLocalized,
                    fill: Color(rgb: env.theme.active.accent)
                )
            }
            .accessibilityLabel(Text("Add Item"))

            QuickActionCard.generate {
                showGenerator = true
            }
            QuickActionCard.totp(count: totpItems.count) {
                showTotpList = true
            }
            QuickActionCard.watchtower(count: watchtowerIssueCount) {
                NotificationCenter.default.post(name: .vaultSwitchToWatchtower, object: nil)
            }
        }
        }
        .sheet(isPresented: $showTotpList) {
            TotpListScreen()
        }
    }

    // MARK: TOTP scroller

    private var totpSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            homeSectionHeader(
                title: LocalizedStringResource("Authenticator Codes").inAppLocalized,
                action: LocalizedStringResource("View All").inAppLocalized
            ) {
                showTotpList = true
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s3) {
                    ForEach(totpItems) { item in
                        TotpCardView(item: item)
                    }
                }
                // 2pt padding so card shadows aren't clipped.
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }
            // Bleed 2pt of the padding back so cards align with section header.
            .padding(.horizontal, -2)
        }
    }

    // MARK: Needs attention

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            homeSectionHeader(
                title: LocalizedStringResource("Needs Attention · \(attentionItems.count)").inAppLocalized
            )

            groupedCard {
                ForEach(Array(attentionItems.enumerated()), id: \.element.id) { idx, item in
                    AttentionCell(
                        item: item,
                        onEdit: { editorTarget = .edit($0) },
                        onOpen: { path.append($0.id) },
                        showDivider: idx < attentionItems.count - 1
                    )
                }
            }
        }
    }

    // MARK: Favorites

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            homeSectionHeader(
                title: LocalizedStringResource("Favorites").inAppLocalized
            )

            groupedCard {
                ForEach(Array(favoriteItems.enumerated()), id: \.element.id) { idx, item in
                    itemRow(item, showDivider: idx < favoriteItems.count - 1)
                }
            }
        }
    }

    // MARK: All items

    private var allItemsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            homeSectionHeader(
                title: LocalizedStringResource("All · \(allItems.count)").inAppLocalized,
                action: LocalizedStringResource("Sort").inAppLocalized
            ) {
                // Cycle through sort modes on tap.
                sortOrder = sortOrder == .updated ? .title : .updated
            }

            groupedCard {
                ForEach(Array(allItems.enumerated()), id: \.element.id) { idx, item in
                    itemRow(item, showDivider: idx < allItems.count - 1)
                }
            }
        }
    }

    // MARK: Empty vault state

    private var emptyVaultState: some View {
        VStack(spacing: Space.s6) {
            // Layered lock crest — an accent-soft halo with the lock glyph, gently
            // elevated so it reads as a deliberate emblem rather than a stray icon.
            ZStack {
                Circle()
                    .fill(Color(rgb: env.theme.active.accentSoft))
                    .frame(width: 116, height: 116)
                    .elevation(.level1)
                PolarisIcon(Icons.lockFill, size: 52)
                    .themedForeground(.accent)
            }

            VStack(spacing: Space.s2) {
                Text("Your vault is empty")
                    .vaultType(.screenTitle)
                    .themedForeground(.primary)
                    .multilineTextAlignment(.center)
                Text("Add your first login, card, or secure note.")
                    .vaultType(.callout)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            Menu {
                newItemMenuItems
            } label: {
                HStack(spacing: Space.s2) {
                    PolarisIcon(Icons.add, size: Metric.iconInline)
                    Text("Add Item")
                }
            }
            .buttonStyle(.themedProminent)
            .padding(.horizontal, Space.s8)
            .padding(.top, Space.s2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Add-item menu

    /// Item-type menu shared by the header "+", the Add quick action, and the empty
    /// state — lets the user choose which kind of item to create (not just a login).
    @ViewBuilder private var newItemMenuItems: some View {
        ForEach(ItemCategory.allCases) { category in
            Button {
                editorTarget = .new(category)
            } label: {
                Label { Text(category.title) } icon: { PolarisIcon(category.iconAsset) }
            }
        }
    }

    // MARK: Shared helpers

    /// Section header matching DS SectionHeader: small caps label + optional tinted action button.
    @ViewBuilder
    private func homeSectionHeader(
        title: LocalizedStringResource,
        action: LocalizedStringResource? = nil,
        onAction: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .vaultType(.sectionLabel)
                .themedForeground(.tertiary)
            Spacer()
            if let action, let onAction {
                Button(action: onAction) {
                    Text(action)
                        .vaultType(.sectionLabel)
                        .foregroundStyle(env.theme.uiTint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, Space.s1)
    }

    /// Grouped card container (surface-base, Radius.lg, hairline stroke).
    @ViewBuilder
    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(rgb: env.theme.active.elevatedBackground))
        .vaultCornerRadius(Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5)
        )
    }

    /// A tappable item row reusing VaultItemRow inside the grouped card.
    @ViewBuilder
    private func itemRow(_ item: VaultItem, showDivider: Bool) -> some View {
        Button {
            path.append(item.id)
        } label: {
            VaultItemRow(item: item, showSpace: selectedFolderId == nil)
                .padding(.horizontal, Space.s4)
                .padding(.vertical, Space.s3)
                .frame(minHeight: Metric.rowHeight)
                .contentShape(.rect)
                .overlay(alignment: .bottom) {
                    if showDivider {
                        Rectangle()
                            .fill(Color(rgb: env.theme.active.separator))
                            .frame(height: 0.5)
                            .padding(.leading, Space.gutter + 40 + Space.s3)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab-switch notifications

extension Notification.Name {
    /// Posted by Home to ask MainTabView to switch to the Search tab.
    static let vaultSwitchToSearch = Notification.Name("vaultSwitchToSearch")
    /// Posted by Home quick-action to switch to the Watchtower tab.
    static let vaultSwitchToWatchtower = Notification.Name("vaultSwitchToWatchtower")
    /// Posted by the Spaces sheet to switch to the Items tab (spaces management).
    static let vaultSwitchToItems = Notification.Name("vaultSwitchToItems")
}
