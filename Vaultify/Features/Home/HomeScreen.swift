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

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if env.repository.items.isEmpty {
                    emptyVaultState
                } else {
                    scrollContent
                }
            }
            .background(Color(rgb: env.theme.active.background).ignoresSafeArea())
            .vaultNavigationDestinations()
            .sheet(item: $editorTarget) { ItemEditorScreen(target: $0) }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .sheet(isPresented: $showGenerator) { GeneratorScreen() }
        }
    }

    // MARK: Main scrollable content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // 1. Header: folder switcher + Add + Settings
                HomeHeaderBar(
                    selectedFolderId: $selectedFolderId,
                    onAddCategory: { editorTarget = .new($0) },
                    onSettings: { showSettings = true }
                )
                .padding(.top, Space.s2)

                // 2. Search entry button (tapping switches to Search tab — we
                //    post a tab-switch notification picked up by MainTabView,
                //    or just present Search as a sheet fallback).
                searchEntryButton
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.s2)
                    .padding(.bottom, Space.s4)

                VStack(alignment: .leading, spacing: Space.s6) {
                    // 3. Quick actions row
                    quickActionsRow

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
    }

    // MARK: Search entry

    private var searchEntryButton: some View {
        Button {
            // Post notification so MainTabView switches to the Search tab.
            NotificationCenter.default.post(name: .vaultSwitchToSearch, object: nil)
        } label: {
            HStack(spacing: Space.s2) {
                PolarisIcon(Icons.search, size: 18)
                    .themedForeground(.secondary)
                Text("Search vault")
                    .vaultType(.callout)
                    .themedForeground(.tertiary)
                Spacer()
            }
            .padding(.horizontal, Space.s3)
            .frame(height: 40)
            .background(
                Color(rgb: env.theme.active.primaryText).opacity(0.07),
                in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Search vault"))
    }

    // MARK: Quick actions

    private var quickActionsRow: some View {
        HStack(spacing: Space.s2) {
            Menu {
                newItemMenuItems
            } label: {
                QuickActionTileLabel(
                    icon: Icons.add,
                    label: LocalizedStringResource("Add Item").inAppLocalized,
                    tint: Color(rgb: env.theme.active.accent)
                )
            }
            .accessibilityLabel(Text("Add Item"))
            QuickActionTile.generate {
                showGenerator = true
            }
            QuickActionTile.totp {
                showTotpList = true
            }
            QuickActionTile.watchtower {
                NotificationCenter.default.post(name: .vaultSwitchToWatchtower, object: nil)
            }
        }
        .sheet(isPresented: $showTotpList) {
            NavigationStack { TotpListScreen() }
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
        ContentUnavailableView {
            Label {
                Text("Your vault is empty")
            } icon: {
                PolarisIcon(Icons.lockFill, size: 48)
                    .themedForeground(.secondary)
            }
        } description: {
            Text("Add your first login, card, or secure note.")
        } actions: {
            Menu {
                newItemMenuItems
            } label: {
                Text("Add Item")
            }
            .buttonStyle(.themedProminent)
        }
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
                        .foregroundStyle(env.theme.active.color(.accent))
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
}
