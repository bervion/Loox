import SwiftUI

/// Home tab — credential-first composition (Design DNA pass, Phase 3):
/// Header → pending shares / approval alerts → TOTP scroller → Needs Attention →
/// Recently Used → Favorites → All items → profile strip → compact quick actions →
/// Empty state when vault is empty.
///
/// The protagonist of this screen is "find and use a credential instantly" — live
/// credential content leads the scroll, profile identity and secondary actions
/// (Add/Generate/2FA/Watchtower) sit below it as a thin strip + compact row.
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
    /// Presents the "New Space" sheet from the persona-empty state's primary CTA
    /// (reuses the existing folder-creation flow — see `personaEmptyState`).
    @State private var showCreateSpaceFromEmptyState = false
    @State private var selectedFolderId: String?
    /// Guards the once-per-launch restore of the remembered Space so it can't
    /// clobber a selection the user makes after launch.
    @State private var didRestoreSelectedSpace = false
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

    /// Capped small (5) so it stays a quick "reach for it again" strip rather than
    /// duplicating the All items list below it.
    private var recentlyUsedItems: [VaultItem] {
        env.repository.recentlyUsed(folder: selectedFolderId, limit: 5)
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
        // A persisted choice (a Space id OR the explicit "All Spaces" sentinel)
        // always wins: auto-select only fills a NEVER-chosen filter, otherwise
        // every return to Home would override the user's "All Spaces".
        guard selectedFolderId == nil,
              env.settings.lastSelectedSpace(persona: activePersonaKey) == nil,
              env.repository.activePersonaSpaces.count == 1,
              env.sharedItems.items.isEmpty else { return }
        selectedFolderId = env.repository.primarySpaceId
    }

    /// Restore the Space filter remembered from a previous launch. Runs once per
    /// launch, before `autoSelectSingleSpace`, so a remembered choice wins. A
    /// remembered Space deleted on another device (stale id) falls back to
    /// "All Spaces" rather than showing an empty filter.
    private func restoreSelectedSpace() {
        guard !didRestoreSelectedSpace else { return }
        didRestoreSelectedSpace = true
        applyRememberedSpace()
    }

    /// The persistence bucket key for the active persona. Falls back to the shared
    /// placeholder before the persona seed lands (or if the resolver is momentarily
    /// nil) so the key stays stable — no crash, no bucket churn.
    private var activePersonaKey: String {
        env.repository.activePersona?.id ?? PersonaID.placeholder
    }

    /// Apply the Space remembered for the active persona, validated against live
    /// folders (a stale id → All Spaces; "" → the explicit "All Spaces" choice).
    /// Reused on active-persona change so the Home filter follows the persona.
    private func applyRememberedSpace() {
        let saved = env.settings.lastSelectedSpace(persona: activePersonaKey)
        selectedFolderId = saved.flatMap { id in
            env.repository.activePersonaSpaces.contains { $0.id == id } ? id : nil
        }
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
                    } else if env.repository.activePersonaItems.isEmpty && env.sharedItems.items.isEmpty {
                        // The vault overall has data, but the ACTIVE persona has nothing to
                        // show (no owned Space yet, or an owned Space with zero items) — the
                        // global gate above would otherwise fall through to `scrollContent`
                        // and render the "All Spaces (0)" scaffolding with an empty card.
                        personaEmptyState
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
            .task { recomputeWatchtowerCount(); restoreSelectedSpace(); autoSelectSingleSpace() }
            // Remember the Home Space across launches (per identity; device-local, not synced).
            // Also re-mirror into the App Group so the AutoFill extension defaults a
            // newly saved login into this same Space (see `mirrorActivePersonaContext`).
            .onChange(of: selectedFolderId) {
                env.settings.setLastSelectedSpace($1, persona: activePersonaKey)
                env.repository.mirrorActivePersonaContext()
            }
            // Switching the active persona re-drives the Home filter to that persona's Space.
            .onChange(of: env.repository.activePersona?.id) { applyRememberedSpace() }
            .onChange(of: env.repository.items.count) { recomputeWatchtowerCount() }
            .onChange(of: env.repository.activePersonaSpaces.count) { autoSelectSingleSpace() }
            // First share arriving on a single-Space setup: release the
            // auto-selected filter so the shared item is actually visible.
            .onChange(of: env.sharedItems.items.count) { old, new in
                if old == 0, new > 0, env.repository.activePersonaSpaces.count == 1 {
                    selectedFolderId = nil
                }
            }
            // New items inherit the Space currently selected on Home (nil = All Spaces →
            // editor falls back to the primary Space).
            .sheet(item: $editorTarget) { ItemEditorScreen(target: $0, preselectedFolderId: selectedFolderId) }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .sheet(isPresented: $showGenerator) { GeneratorScreen() }
            .sheet(isPresented: $showFolderPicker) { HomeFolderPickerSheet(selectedFolderId: $selectedFolderId) }
            // Persona-empty state's "Create a Space" CTA — reuses the standard Space
            // creation flow; the newly owned Space then satisfies the persona-scoped
            // gate above on its own (no manual filter/state wiring needed here).
            .sheet(isPresented: $showCreateSpaceFromEmptyState) { FolderEditorSheet(folder: nil) }
            // Anchored at the stable root, NOT inside pendingSharesSection: cancelling
            // the last pending share removes that conditional view mid-dismiss, which
            // would strand the sheet binding and re-present a stale record later.
            .sheet(item: $homeResumeShare) { ShareResumeStepperSheet(share: $0) }
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
                    // 0. Identity context line — a thin "acting as" strip, not a card.
                    // Sits at the very top so which persona you're operating as is
                    // always visible (INV-R03 discoverability) without competing with
                    // the protagonist band below.
                    profileRow

                    // Protagonist band — live/urgent credential content leads the screen
                    // (find & use a credential instantly). Order: time-sensitive share/approval
                    // alerts, then TOTP, Needs Attention, Recently Used, Favorites, All items.

                    // 1. Shares I sent that are still pending (design 12a): first-class,
                    // persists across app kill — not tied to whichever sheet created it.
                    if !pendingOutgoingShares.isEmpty {
                        pendingSharesSection
                    }

                    // 2. Pending approval requests (owner side): one → open the
                    // ceremony directly; several → the notifications inbox.
                    if !env.approvalCoordinator.pendingOwnerRequests.isEmpty {
                        approvalAttentionRow
                    }

                    // 3. TOTP scroller (only when items with TOTP exist)
                    if !totpItems.isEmpty {
                        totpSection
                    }

                    // 4. Needs attention (max 4)
                    if !attentionItems.isEmpty {
                        attentionSection
                    }

                    // 5. Recently used — "reach for it again" signal, distinct from All
                    // items' edit-time sort. Only shown once the vault is big enough for
                    // it to add signal: on a small vault everything is already on screen
                    // and this strip just duplicates the list right below it.
                    if !recentlyUsedItems.isEmpty, allItems.count > 5 {
                        recentlyUsedSection
                    }

                    // 6. Favorites
                    if !favoriteItems.isEmpty {
                        favoritesSection
                    }

                    // 7. All items (pinned first)
                    allItemsSection

                    // 8. Quick-actions grid (Add/Generate/2FA/Watchtower) — secondary,
                    // 2×2 horizontal pills so Vietnamese labels never truncate.
                    quickActionsGrid
                }
                .padding(.horizontal, Space.gutter)
                // Bottom inset so the floating tab bar never obscures the last row.
                .padding(.bottom, TabBarMetric.contentBottomInset)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Pending outgoing shares (design 12a)

    @State private var homeResumeShare: ItemShareRecord?

    /// Shares I sent that haven't reached Active yet — ephemeral by
    /// construction: once `SharingStore` advances a record to `.active` (or
    /// it's cancelled/removed) it drops out of this filter and the row
    /// disappears on its own, no extra bookkeeping needed here.
    private var pendingOutgoingShares: [ItemShareRecord] {
        env.sharingStore.shares
            .filter { $0.status != .active }
            .sorted { $0.createdAtUnixMs > $1.createdAtUnixMs }
    }

    private var pendingSharesSection: some View {
        VStack(spacing: Space.s2) {
            ForEach(pendingOutgoingShares) { share in
                Button { homeResumeShare = share } label: {
                    pendingShareRowLabel(share)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func pendingShareRowLabel(_ share: ItemShareRecord) -> some View {
        let title = env.repository.item(id: share.itemId)?.title ?? appString("an item")
        // Status color language: orange = waiting on them, green = waiting on YOU
        // (ready to confirm the safety code).
        let waitingOnOwner = share.status == .readyForCeremony
        return HStack(spacing: Space.s3) {
            StatusDot(kind: waitingOnOwner ? .active : .pending)
            PolarisIcon(Icons.share, size: Metric.iconInline)
                .themedForeground(waitingOnOwner ? .success : .warning)
            Group {
                if waitingOnOwner {
                    Text("Sharing \"\(title)\" is ready to confirm")
                } else {
                    Text("Sharing \"\(title)\" is waiting for \(share.recipientLabel)")
                }
            }
            .vaultType(.body).themedForeground()
            .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: Space.s2)
            PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.secondary)
        }
        .padding(Space.s4)
        .frame(minHeight: Metric.hitMin)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
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

    /// Subtitle under the active persona name: its kind, plus that persona's own
    /// email when resolvable. Uses the persona-scoped resolver so a strictAnonymous
    /// persona never shows another identity's email (INV-R03).
    private var personaSubtitle: String {
        guard let persona = env.repository.activePersona else { return appString("Set up your identity") }
        let kind = PersonaKindStyle.label(persona.kind)
        // Kind + email, comma-joined (user-chosen format: "Cá nhân, email…").
        if let email = env.repository.identityUsername(forPersona: persona), !email.isEmpty {
            return "\(kind), \(email)"
        }
        return kind
    }

    /// Identity card at the top of the scroll: avatar + active persona name + email
    /// on a white surface card. The user chose the card treatment over a thin strip —
    /// the identity deserves a visible anchor, and the card reads cleanly against the
    /// grouped background without competing with the credential band below.
    private var profileRow: some View {
        Button { uiState.homePath.append(ProfileRoute()) } label: {
            HStack(spacing: Space.s3) {
                profileAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: env.repository.activePersona?.displayName ?? appString("Profile"))
                        .vaultType(.headline).themedForeground().lineLimit(1)
                    Text(verbatim: personaSubtitle)
                        .vaultType(.subhead).themedForeground(.secondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: env.theme.active.elevatedBackground))
            .vaultCornerRadius(Radius.lg)
            .elevation(.level1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: "\(env.repository.activePersona?.displayName ?? appString("Profile")), \(personaSubtitle)"))
    }

    /// 44pt avatar — stored image, letter-avatar, or a person glyph when no identity.
    /// Radius concentric to the card (outer lg, inset s4) so nested corners stay parallel.
    @ViewBuilder private var profileAvatar: some View {
        let avatarSize: CGFloat = 44
        let cornerRadius = Radius.concentric(outer: Radius.lg, inset: Space.s4)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // The ACTIVE persona's own card — never another persona's (an anonymous
        // persona must not wear the personal photo).
        if let identity = env.repository.activeProfileItem {
            if let image = env.repository.avatarImage(for: identity.id) {
                Image(platformImage: image).resizable().scaledToFill()
                    .frame(width: avatarSize, height: avatarSize).clipShape(shape)
            } else {
                ItemThumbnail(title: identity.title, category: .identity, iconAsset: nil, size: avatarSize)
                    .clipShape(shape)
            }
        } else {
            PolarisIcon(Icons.person, size: Metric.iconInline)
                .themedForeground(.accent)
                .frame(width: avatarSize, height: avatarSize)
                .background(Color(rgb: env.theme.active.accentSoft), in: shape)
        }
    }

    // MARK: Quick actions

    /// Quick actions as a 2×2 grid of horizontal pills: Add · Generate · 2FA · Watchtower.
    /// Half-width pills give Vietnamese labels ("Tạo mật khẩu") room to render whole —
    /// a single row of four truncated them. Still secondary to the credential content
    /// above: counts on 2FA/Watchtower stay a small trailing badge, not a headline.
    private var quickActionsGrid: some View {
        // One GlassEffectContainer for all glass views (4 pills + badges) → a single
        // backdrop layer; fixes the per-frame glass-update warning on theme changes.
        VaultGlassGroup {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s3),
                            GridItem(.flexible(), spacing: Space.s3)],
                  spacing: Space.s3) {
            // Add — presents the item-type menu (uses ic_page_add, matches the header).
            Menu {
                newItemMenuItems
            } label: {
                QuickActionCardLabel(
                    icon: Icons.pageAdd,
                    label: LocalizedStringResource("Add Item").inAppLocalized,
                    tint: Color(rgb: env.theme.active.accent)
                )
            }
            // Plain tile menu — macOS would otherwise draw a bordered pull-down button
            // around the whole tile, breaking the compact row's visual consistency.
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
                title: LocalizedStringResource("Needs Attention (\(attentionItems.count))").inAppLocalized
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

    // MARK: Recently used

    private var recentlyUsedSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            homeSectionHeader(
                title: LocalizedStringResource("Recently Used").inAppLocalized
            )

            groupedCard {
                ForEach(Array(recentlyUsedItems.enumerated()), id: \.element.id) { idx, item in
                    itemRow(item, showDivider: idx < recentlyUsedItems.count - 1)
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
        // .center (not .lastTextBaseline): both sides render the same
        // `.sectionLabel` style, so centering is visually identical while
        // staying correct once the invisible hit-target frames below add height.
        HStack(alignment: .center) {
            Button { showFolderPicker = true } label: {
                HStack(spacing: Space.s1) {
                    spaceTitleText.vaultType(.sectionLabel)
                    Text(verbatim: "(\(allItems.count))").vaultType(.sectionLabel)
                    PolarisIcon(Icons.chevronDown, size: 12).themedForeground(.tertiary)
                }
                .themedForeground(.tertiary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(minHeight: Metric.hitMin)
            .contentShape(Rectangle())

            Spacer()

            // A real menu with a checkmark, not a silent toggle — tapping "Sort"
            // and seeing nothing happen read as a dead button.
            Menu {
                Picker("Sort", selection: $sortOrder) {
                    ForEach(VaultSort.allCases) { sort in
                        Text(sort.label).tag(sort)
                    }
                }
            } label: {
                Text(LocalizedStringResource("Sort").inAppLocalized)
                    .vaultType(.sectionLabel)
                    .foregroundStyle(env.theme.uiTint)
                    .frame(minHeight: Metric.hitMin)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .padding(.bottom, Space.s1)
    }

    /// Selected Space name, or the localized "All Spaces" fallback (nil filter).
    private var spaceTitleText: Text {
        if let id = selectedFolderId, let folder = env.repository.activePersonaSpaces.first(where: { $0.id == id }) {
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
                Text("Everything is encrypted on this iPhone before it's stored.")
                    .vaultType(.footnote)
                    .themedForeground(.tertiary)
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

    /// Shown when the vault overall has data, but the ACTIVE persona has nothing
    /// (no owned Space yet, or an owned Space with zero items) — e.g. a persona
    /// whose only Space was deleted, or one just switched to for the first time.
    /// Distinct from `emptyVaultState`: this is per-identity, not "first run".
    private var personaEmptyState: some View {
        VStack(spacing: Space.s6) {
            ZStack {
                Circle()
                    .fill(Color(rgb: env.theme.active.accentSoft))
                    .frame(width: 116, height: 116)
                    .elevation(.level1)
                PolarisIcon(env.repository.activePersonaSpaces.isEmpty ? Icons.folder : Icons.lockFill, size: 52)
                    .themedForeground(.accent)
            }

            VStack(spacing: Space.s2) {
                Text("Nothing here yet")
                    .vaultType(.screenTitle)
                    .themedForeground(.primary)
                    .multilineTextAlignment(.center)
                Text(personaEmptyStateSubtitle)
                    .vaultType(.callout)
                    .themedForeground(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            if env.repository.activePersonaSpaces.isEmpty {
                // No owned Space: steer to creating one first (a new item here would
                // otherwise fall back to Unfiled, which only the default identity owns).
                Button { showCreateSpaceFromEmptyState = true } label: {
                    HStack(spacing: Space.s2) {
                        PolarisIcon(Icons.addCircle, size: Metric.iconInline)
                        Text("Create a Space")
                    }
                }
                .buttonStyle(.themedProminent)
                .padding(.horizontal, Space.s8)
                .padding(.top, Space.s2)
            } else {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var personaEmptyStateSubtitle: LocalizedStringKey {
        env.repository.activePersonaSpaces.isEmpty
            ? "This identity doesn’t have a Space yet. Create one to start adding items."
            : "Add your first item to this identity’s vault."
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
        // .center (not .lastTextBaseline): title and action share the same
        // `.sectionLabel` style, so centering is visually identical while
        // staying correct once the action's invisible hit-target frame adds height.
        HStack(alignment: .center) {
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
                .frame(minHeight: Metric.hitMin)
                .contentShape(Rectangle())
            }
        }
        .padding(.bottom, Space.s1)
    }

    /// Grouped card container (surface-base, Radius.lg). Card-diet: the hairline stroke is
    /// dropped in favor of `.elevation(.level1)` — the soft shadow plus the
    /// elevatedBackground/groupedBackground contrast still reads as grouped in both light
    /// and dark mode without an extra border line.
    @ViewBuilder
    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Color(rgb: env.theme.active.elevatedBackground))
        .vaultCornerRadius(Radius.lg)
        .elevation(.level1)
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
