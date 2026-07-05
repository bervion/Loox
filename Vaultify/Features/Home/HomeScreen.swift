import SwiftUI

/// Home tab — DS-spec composition (Phase 5):
/// Header → Search entry → Quick actions → TOTP scroller → Needs Attention →
/// Favorites → All items → Empty state when vault is empty.
///
/// `selectedFolderId` nil = "All Spaces" (no folder filter). Every section is
/// filtered by the selected folder and renders only when non-empty.
struct HomeScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(UIStateStore.self) private var uiState
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var editorTarget: EditorTarget?
    @State private var showSettings = false
    @State private var showGenerator = false
    @State private var showTotpList = false
    @State private var showFolderPicker = false
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
        // Shared-with-me projections are first-class list citizens (V1.2).
        // They live in no Space yet ALWAYS join the feed — single-Space users
        // are auto-filtered to their folder, and a Space filter must not make
        // somebody's share invisible (review M1).
        let pool = env.repository.allItems(folder: selectedFolderId) + env.sharedItems.items
        let sorted = sortOrder.apply(pool)
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

    /// With exactly one Space, default the filter to that Space (not "All Spaces") so its name
    /// shows in the "All" section title. Only fills an unset selection — never overrides a
    /// choice the user made, and stays out of the way once a second Space exists.
    private func autoSelectSingleSpace() {
        // With shared items in play there are effectively TWO sources —
        // stay on "All Spaces" so the shares are never filtered out.
        guard selectedFolderId == nil, env.repository.folders.count == 1,
              env.sharedItems.items.isEmpty else { return }
        selectedFolderId = env.repository.folders.first?.id
    }

    var body: some View {
        @Bindable var uiState = uiState
        return NavigationStack(path: $uiState.homePath) {
            // ZStack lets the header float over scroll content so glass blurs it.
            ZStack(alignment: .top) {
                Group {
                    // A vault that's empty but RECEIVING shares still has a feed.
                    if env.repository.items.isEmpty && env.sharedItems.items.isEmpty {
                        emptyVaultState
                    } else {
                        scrollContent
                    }
                }

                // Header overlays the scroll content — glass blurs whatever scrolls beneath.
                HomeHeaderBar(
                    onAddCategory: { editorTarget = .new($0) },
                    onSettings: {
                        // macOS opens the native Settings window (⌘,) instead of the
                        // iOS-style sheet — the platform-idiomatic home for settings.
                        #if os(macOS)
                        openSettings()
                        #else
                        showSettings = true
                        #endif
                    }
                )
            }
            .environment(\.vaultHeaderScrolledUnder, scrolledUnder)
            .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
            .platformHiddenNavigationBar()
            .vaultNavigationDestinations()
            .navigationDestination(for: ProfileRoute.self) { _ in ProfileScreen() }
            .task { recomputeWatchtowerCount(); autoSelectSingleSpace() }
            .onChange(of: env.repository.items.count) { recomputeWatchtowerCount() }
            .onChange(of: env.repository.folders.count) { autoSelectSingleSpace() }
            // First share arriving on a single-Space setup: release the
            // auto-selected filter so the shared item is actually visible.
            .onChange(of: env.sharedItems.items.count) { old, new in
                if old == 0, new > 0, env.repository.folders.count == 1 {
                    selectedFolderId = nil
                }
            }
            // New items inherit the Space currently selected on Home (nil = All Spaces →
            // editor falls back to the primary Space).
            .sheet(item: $editorTarget) { ItemEditorScreen(target: $0, preselectedFolderId: selectedFolderId) }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .sheet(isPresented: $showGenerator) { GeneratorScreen() }
            .sheet(isPresented: $showFolderPicker) { HomeFolderPickerSheet(selectedFolderId: $selectedFolderId) }
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
                    // 2. Profile entry (avatar + name + email) → opens the Profile sheet.
                    profileRow

                    // 3. Quick actions grid (Reminders-style colour cards)
                    quickActionsGrid

                    // 4. Pending approval requests (owner side): one → open the
                    // ceremony directly; several → the notifications inbox.
                    if !env.approvalCoordinator.pendingOwnerRequests.isEmpty {
                        approvalAttentionRow
                    }

                    // 5. TOTP scroller (only when items with TOTP exist)
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

    // MARK: Approval attention row

    @State private var homePresentedApproval: ApprovalCoordinator.PendingOwnerRequest?

    @ViewBuilder private var approvalAttentionRow: some View {
        let requests = env.approvalCoordinator.pendingOwnerRequests
        Group {
            if requests.count == 1, let single = requests.first {
                Button { homePresentedApproval = single } label: {
                    approvalRowLabel(count: 1)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(value: NotificationsRoute()) {
                    approvalRowLabel(count: requests.count)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(item: $homePresentedApproval) { pending in
            ApprovalRequestSheet(
                pending: pending,
                itemTitle: env.repository.item(id: pending.request.itemId)?.title
                    ?? appString("an item"),
                onFinished: {
                    env.approvalCoordinator.clearPending(requestId: pending.request.requestId)
                })
        }
    }

    private func approvalRowLabel(count: Int) -> some View {
        HStack(spacing: Space.s3) {
            Circle().fill(env.theme.active.color(.success)).frame(width: 8, height: 8)
            PolarisIcon(Icons.shield, size: Metric.iconInline).themedForeground(.warning)
            Text("Approval needed").vaultType(.body).themedForeground()
            Spacer()
            Text("\(count)").themedForeground(.secondary)
            PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.secondary)
        }
        .padding(Space.s4)
        .frame(minHeight: Metric.hitMin)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }

    // MARK: Profile row

    private var profileEmail: String? {
        guard let value = env.repository.defaultIdentity?.fields.first(where: { $0.kind == .email })?.value,
              !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    /// "Name · email" on one line; falls back to whichever part exists.
    private func profileSubtitle(name: String) -> String {
        [name, profileEmail].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
    }

    /// Profile entry row above the quick actions: avatar + "Profile" title + the default
    /// identity's name & email. Tapping opens the Profile sheet (same as the old header icon).
    private var profileRow: some View {
        Button { uiState.homePath.append(ProfileRoute()) } label: {
            HStack(spacing: Space.s3) {
                profileAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text("Profile").vaultType(.headline).themedForeground()
                    if let identity = env.repository.defaultIdentity {
                        // Name + email on a single line (email appended after the name).
                        Text(verbatim: profileSubtitle(name: identity.title))
                            .vaultType(.subhead).themedForeground(.secondary).lineLimit(1)
                    } else {
                        Text("Set up your identity")
                            .vaultType(.subhead).themedForeground(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: Space.s2)
                PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: env.theme.active.elevatedBackground))
            .vaultCornerRadius(Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// 44pt circular avatar — stored image, letter-avatar, or a person glyph when no identity.
    @ViewBuilder private var profileAvatar: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if let identity = env.repository.defaultIdentity {
            if let image = env.repository.avatarImage(for: identity.id) {
                Image(platformImage: image).resizable().scaledToFill()
                    .frame(width: 44, height: 44).clipShape(shape)
            } else {
                ItemThumbnail(title: identity.title, category: .identity, iconAsset: nil, size: 44)
                    .clipShape(shape)
            }
        } else {
            PolarisIcon(Icons.person, size: Metric.iconUtility)
                .themedForeground(.accent)
                .frame(width: 44, height: 44)
                .background(Color(rgb: env.theme.active.accentSoft), in: shape)
        }
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
            // Plain card menu — macOS would otherwise draw a bordered pull-down button
            // around the whole card, breaking the 2-up grid's visual consistency.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
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
                        onOpen: { uiState.homePath.append($0.id) },
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
            allItemsHeader

            groupedCard {
                ForEach(Array(allItems.enumerated()), id: \.element.id) { idx, item in
                    itemRow(item, showDivider: idx < allItems.count - 1)
                }
            }
        }
    }

    /// "All" section header — the Space switcher (name + item count + chevron) opening the
    /// picker, with the Sort action trailing. The switcher moved here from the top header bar.
    private var allItemsHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            Button { showFolderPicker = true } label: {
                HStack(spacing: Space.s1) {
                    spaceTitleText.vaultType(.sectionLabel)
                    Text(verbatim: "· \(allItems.count)").vaultType(.sectionLabel)
                    PolarisIcon(Icons.chevronDown, size: 12).themedForeground(.tertiary)
                }
                .themedForeground(.tertiary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                sortOrder = sortOrder == .updated ? .title : .updated
            } label: {
                Text(LocalizedStringResource("Sort").inAppLocalized)
                    .vaultType(.sectionLabel)
                    .foregroundStyle(env.theme.uiTint)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, Space.s1)
    }

    /// Selected Space name, or the localized "All Spaces" fallback (nil filter).
    private var spaceTitleText: Text {
        if let id = selectedFolderId, let folder = env.repository.folders.first(where: { $0.id == id }) {
            return Text(verbatim: folder.name)
        }
        return Text("All Spaces")
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
            uiState.homePath.append(item.id)
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
