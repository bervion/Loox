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
    /// Regular width (iPad/Mac): the sidebar carries the persona avatar row
    /// (Settings idiom), so Home drops its identity card there.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(UIStateStore.self) private var uiState
    // Present in the compact-iOS UIKit shell; nil on the iPad/Mac sidebar (which
    // navigates via its own SwiftUI stack). See `openItem`/`openSettingsScreen`.
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif
    @State private var editorTarget: EditorTarget?
    /// The create-item type picker + the category chosen there, presented as the
    /// editor once the picker finishes dismissing.
    @State private var showItemTypePicker = false
    @State private var pendingNewCategory: ItemCategory?
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
    @State private var scrolledUnder = false
    /// Cached Watchtower issue count for the quick-action badge (recomputed on appear and
    /// when the item set changes — `PasswordAudit.analyze` is too costly to run per render).
    @State private var watchtowerIssueCount = 0
    /// Home layout edit mode — flips the screen into the section arranger (reorder +
    /// show/hide), driven from the header's edit button.
    @State private var isEditingLayout = false

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
        // Newest first (most recently updated). Sort is fixed — the old Home sort control
        // was removed; the full list in Search is where broader browsing happens.
        let sorted = VaultSort.updated.apply(pool)
        // Pinned items float to the top, keeping the sort within each group.
        return sorted.filter(\.pinned) + sorted.filter { !$0.pinned }
    }

    /// Security issues (weak + reused + missing 2FA) for the Watchtower badge —
    /// matches the Watchtower screen's synchronous count (HIBP/pwned excluded; that
    /// needs the network). Scoped to the ACTIVE persona, exactly like the
    /// Watchtower screen, so the badge and the screen never disagree.
    private func recomputeWatchtowerCount() {
        let health = PasswordAudit.analyze(env.repository.activePersonaItems)
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
                // BOTH content layers stay mounted; the edit-mode toggle only cross-fades
                // opacity/scale. Inserting either side mid-animation (the editor's
                // UIKit-backed List on the way in, the whole feed on the way out) costs a
                // build + layout pass inside the animation window — more than one 8.3ms
                // frame at 120Hz, which reads as a one-beat hitch on ProMotion. Keeping
                // them resident moves that cost to launch, where it's invisible, and as a
                // side effect the feed's scroll position survives an edit session.
                Group {
                    // The feed (or its empty states — those keep the PROFILE ROW so
                    // switching persona stays reachable; a vault that's empty but
                    // RECEIVING shares still has a feed).
                    if env.repository.items.isEmpty && env.sharedItems.items.isEmpty {
                        emptyStateScaffold { emptyVaultState }
                    } else if env.repository.activePersonaItems.isEmpty && env.sharedItems.items.isEmpty {
                        // The vault overall has data, but the ACTIVE persona has nothing to
                        // show (no owned Space yet, or an owned Space with zero items) — the
                        // global gate above would otherwise fall through to `scrollContent`
                        // and render the "All Spaces (0)" scaffolding with an empty card.
                        emptyStateScaffold { personaEmptyState }
                    } else {
                        scrollContent
                    }
                }
                // Pure cross-fade — the springy scale-and-fade re-composed both
                // resident layers every frame and still hitched a beat on entry
                // (owner 260723: keep it simple and smooth over fancy).
                .opacity(isEditingLayout ? 0 : 1)
                .allowsHitTesting(!isEditingLayout)
                .accessibilityHidden(isEditingLayout)

                // Section arranger (reorder + show/hide) — resident at opacity 0 outside
                // edit mode; its profile row is intentionally omitted. Born with edit mode
                // already active so UIKit's editing layout never runs inside the toggle
                // animation (see HomeLayoutEditor).
                HomeLayoutEditor()
                    .opacity(isEditingLayout ? 1 : 0)
                    .allowsHitTesting(isEditingLayout)
                    .accessibilityHidden(!isEditingLayout)

                // Header overlays the scroll content — glass blurs whatever scrolls
                // beneath. Declared last so it's topmost for hit testing (the Done button
                // must stay tappable over the editor); with no view insertion left in the
                // toggle, layer order no longer affects the animation.
                HomeHeaderBar(
                    isEditingLayout: $isEditingLayout,
                    onAdd: { showItemTypePicker = true },
                    onNotifications: { openNotifications() },
                    onSettings: {
                        // macOS opens the native Settings window (⌘,) instead of the
                        // iOS-style sheet — the platform-idiomatic home for settings.
                        #if os(macOS)
                        openSettings()
                        #else
                        openSettingsScreen()
                        #endif
                    }
                )
            }
            .environment(\.vaultHeaderScrolledUnder, scrolledUnder)
            .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
            .platformHiddenNavigationBar()
            .vaultNavigationDestinations()
            .navigationDestination(for: ProfileRoute.self) { _ in ProfileScreen().fullScreenPush() }
            .navigationDestination(for: SettingsRoute.self) { _ in SettingsScreen().fullScreenPush() }
            .task {
                recomputeWatchtowerCount(); restoreSelectedSpace(); autoSelectSingleSpace()
                // First unlocked look at Home is where the tour makes sense —
                // the vault exists and its own surfaces are on screen. Repeat
                // visits self-suppress once the flow has been answered.
                env.tutorial.startIfNeeded(.firstRun)
            }
            .analyticsScreen("home")
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
            // Item-type picker → present the editor once it finishes dismissing.
            .sheet(isPresented: $showItemTypePicker, onDismiss: {
                if let category = pendingNewCategory {
                    pendingNewCategory = nil
                    editorTarget = .new(category)
                }
            }) {
                ItemTypePickerSheet { pendingNewCategory = $0; showItemTypePicker = false }
            }
            .sheet(isPresented: $showGenerator) { GeneratorScreen() }
            // TOTP list is reachable from both the Authenticator section header and the
            // Quick Actions tile, so its sheet anchors at the stable root — not on a section
            // the user can now hide (which would strand the trigger).
            .sheet(isPresented: $showTotpList) { TotpListScreen() }
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
                    // Identity context line — a thin "acting as" strip pinned above the
                    // customizable band so which persona you're operating as is always
                    // visible (INV-R03). Never hidden or reordered (see `HomeSection`).
                    // Regular width: the sidebar's avatar row carries this instead.
                    if horizontalSizeClass != .regular { profileRow }

                    // Customizable protagonist band — order and visibility come from
                    // `SettingsStore` (edited via the header's layout editor). Each section
                    // still renders only when it has content; `allItems` / `quickActions`
                    // always do. The default order matches the original hand-tuned sequence.
                    ForEach(orderedSections) { section in
                        if !isHidden(section) {
                            sectionView(section)
                        }
                    }
                }
                .padding(.horizontal, Space.gutter)
                // Bottom inset so the floating tab bar never obscures the last row.
                .padding(.bottom, TabBarMetric.contentBottomInset)
            }
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Section layout (order + visibility)

    /// Sections in the user's saved order (falling back to the canonical default), with any
    /// newly shipped section appended so it can't silently vanish.
    private var orderedSections: [HomeSection] {
        HomeSection.ordered(savedOrder: env.settings.homeSectionOrder)
    }

    private func isHidden(_ section: HomeSection) -> Bool {
        env.settings.homeHiddenSections.contains(section.rawValue)
    }

    /// Resolves a section id to its view, preserving each section's original
    /// "only render when it has content" rule (an empty section stays absent).
    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        switch section {
        case .pendingShares:
            if !pendingOutgoingShares.isEmpty { pendingSharesSection }
        case .approvals:
            if !env.approvalCoordinator.pendingOwnerRequests.isEmpty { approvalAttentionRow }
        case .totp:
            if !totpItems.isEmpty { totpSection }
        case .attention:
            if !attentionItems.isEmpty { attentionSection }
        case .recentlyUsed:
            if !recentlyUsedItems.isEmpty, allItems.count > 5 { recentlyUsedSection }
        case .favorites:
            if !favoriteItems.isEmpty { favoritesSection }
        case .allItems:
            allItemsSection
        case .quickActions:
            // Regular width (iPad): the sidebar carries Quick Actions as its own
            // section, so Home drops the grid there. Narrow multitasking collapses
            // to compact — no sidebar — and the grid comes back with it.
            if horizontalSizeClass != .regular { quickActionsGrid }
        }
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
                Button { openNotifications() } label: {
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

    /// Subtitle under the active persona name — shared with the sidebar's
    /// avatar row (see `PersonaDisplay`).
    private var personaSubtitle: String { PersonaDisplay.subtitle(env) }

    /// Identity card at the top of the scroll: avatar + active persona name + email
    /// on a white surface card. The user chose the card treatment over a thin strip —
    /// the identity deserves a visible anchor, and the card reads cleanly against the
    /// grouped background without competing with the credential band below.
    private var profileRow: some View {
        Button { openProfile() } label: {
            HStack(spacing: Space.s3) {
                profileAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: PersonaDisplay.name(env))
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
        .accessibilityLabel(Text(verbatim: "\(PersonaDisplay.name(env)), \(personaSubtitle)"))
    }

    /// 44pt circular avatar — extracted to `PersonaAvatarView`, shared with the
    /// iPad/Mac sidebar profile row.
    private var profileAvatar: some View { PersonaAvatarView(size: 44) }

    // MARK: Quick actions

    /// Quick actions as a titled group card holding a 2×2 grid of grey tiles:
    /// Add · Generate · 2FA · Security. Each tile pairs a single-hue accent duotone glyph
    /// with a one-line label; half-width tiles give Vietnamese labels ("Tạo mật khẩu") room
    /// to render whole. Still secondary to the credential content above: counts on
    /// 2FA/Security stay a small trailing badge, not a headline.
    private var quickActionsGrid: some View {
        QuickActionsGroupCard(
            title: LocalizedStringResource("Quick Actions").inAppLocalized,
            subtitle: LocalizedStringResource("Jump straight to what you need").inAppLocalized,
            // Short labels pair with short and long with long, so each row's
            // side-by-side vs stacked decision (measured per row in
            // `QuickActionsGroupCard`) degrades one row at a time.
            items: [
                .init(icon: "dt_square_plus",
                      label: LocalizedStringResource("Add Item").inAppLocalized,
                      tint: QuickActionsGroupCard.addTint,
                      tutorialAnchorID: TutorialAnchorID.homeAddItem,
                      action: { showItemTypePicker = true }),
                .init(icon: "dt_shield_keyhole",
                      label: LocalizedStringResource("Security").inAppLocalized,
                      tint: QuickActionsGroupCard.securityTint,
                      count: watchtowerIssueCount,
                      tutorialAnchorID: TutorialAnchorID.homeSecurity,
                      action: { NotificationCenter.default.post(name: .vaultSwitchToWatchtower, object: nil) }),
                .init(icon: "dt_key",
                      label: LocalizedStringResource("Generate Password").inAppLocalized,
                      tint: QuickActionsGroupCard.generateTint,
                      action: { showGenerator = true }),
                .init(icon: "dt_clock",
                      label: LocalizedStringResource("2FA Codes").inAppLocalized,
                      tint: QuickActionsGroupCard.totpTint,
                      count: totpItems.count,
                      action: { showTotpList = true }),
            ]
        )
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
                        onOpen: { openItem($0.id) },
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
                    itemRow(item, context: "recent", showDivider: idx < recentlyUsedItems.count - 1)
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
                    itemRow(item, context: "favorite", showDivider: idx < favoriteItems.count - 1)
                }
            }
        }
    }

    // MARK: All items

    /// Max rows shown in the Home "All items" preview card before "See all".
    private let allItemsPreviewLimit = 5

    /// "All items" preview card: the Space filter as the card's own dropdown title, a short
    /// description, up to `allItemsPreviewLimit` rows (newest first), and a "See all" that
    /// opens the full list in Search — scoped to this Space, keyboard suppressed.
    private var allItemsSection: some View {
        let preview = Array(allItems.prefix(allItemsPreviewLimit))
        return VStack(alignment: .leading, spacing: 0) {
            allItemsCardHeader
                .padding(.horizontal, Space.s4)
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s2)

            ForEach(Array(preview.enumerated()), id: \.element.id) { idx, item in
                itemRow(item, context: "all", showDivider: idx < preview.count - 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: env.theme.active.elevatedBackground))
        .vaultCornerRadius(Radius.lg)
        .elevation(.level1)
    }

    /// Card header: the Space filter as a headline-size dropdown title (opens the Space
    /// picker) with a quiet grey "See all" trailing. No description, item count, or sort
    /// control — the title plus the rows below make the card self-evident; sort is fixed
    /// newest-first.
    private var allItemsCardHeader: some View {
        // Title row only, headline size. NATURAL height (no 44pt frame) so it sits tight to
        // the rows — a min-height frame here would center the title in a tall row and open a gap.
        HStack(alignment: .center) {
            Button { showFolderPicker = true } label: {
                HStack(spacing: Space.s1) {
                    spaceTitleText
                        .vaultType(.headline)
                        .themedForeground(.primary)
                    PolarisIcon(Icons.chevronDown, size: 13)
                        .foregroundStyle(env.theme.uiTint)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Spacer(minLength: Space.s2)

            Button { openAllItemsList() } label: {
                HStack(spacing: 3) {
                    Text(LocalizedStringResource("See all").inAppLocalized)
                        .vaultType(.subhead)
                    PolarisIcon(Icons.chevronRight, size: 11)
                }
                // Quiet grey (not accent) — a low-key affordance, per request.
                .themedForeground(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// Open the full item list as a REAL push (Back returns right here), scoped
    /// to the current Home Space — not a tab jump into Search.
    private func openAllItemsList() {
        let route = VaultRoute.filtered(ItemFilter(spaceId: selectedFolderId))
        if let navigator { navigator.push { vaultRouteDestination(route) } }
        else { uiState.homePath.append(route) }
    }

    /// Selected Space name, or the localized "All Spaces" fallback (nil filter).
    private var spaceTitleText: Text {
        if let id = selectedFolderId, let folder = env.repository.activePersonaSpaces.first(where: { $0.id == id }) {
            return Text(verbatim: folder.name)
        }
        return Text("All Spaces")
    }

    // MARK: Empty vault state

    /// Shared chrome for both empty states: the header spacer + the persona
    /// profile row above the empty content, inside a scroll view — the same
    /// top structure as `scrollContent`, so switching identity stays possible
    /// (and the header blur keeps working) even when there is nothing to list.
    private func emptyStateScaffold<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VaultHeaderScrollSpacer(scrolledUnder: $scrolledUnder)
                VStack(alignment: .leading, spacing: Space.s6) {
                    if horizontalSizeClass != .regular { profileRow }
                    content()
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s8)
                }
                .padding(.horizontal, Space.gutter)
                .padding(.bottom, TabBarMetric.contentBottomInset)
            }
        }
        .scrollIndicators(.hidden)
    }

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

            Button {
                showItemTypePicker = true
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
                Button {
                    showItemTypePicker = true
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

    // MARK: Navigation — compact iOS pushes onto the UIKit shell (native slide
    // that covers the tab bar); the iPad/Mac sidebar (no navigator) falls back to
    // its own SwiftUI stack path so its navigation is unchanged.

    private func openItem(_ id: String) {
        if let navigator { navigator.push { ItemDetailScreen(itemID: id) } }
        else { uiState.homePath.append(id) }
    }
    private func openSettingsScreen() {
        if let navigator { navigator.push { SettingsScreen() } }
        else { uiState.homePath.append(SettingsRoute()) }
    }
    private func openProfile() {
        if let navigator { navigator.push { ProfileScreen() } }
        else { uiState.homePath.append(ProfileRoute()) }
    }
    private func openNotifications() {
        if let navigator { navigator.push { NotificationsScreen() } }
        else { uiState.homePath.append(NotificationsRoute()) }
    }

    /// A tappable item row reusing VaultItemRow inside the grouped card.
    @ViewBuilder
    private func itemRow(_ item: VaultItem, context: String, showDivider: Bool) -> some View {
        Button {
            openItem(item.id)
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
                            .padding(.leading, Space.s4 + 40 + Space.s3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vault.item.\(item.id).\(context)")
    }
}

// MARK: - Tab-switch notifications

extension Notification.Name {
    /// Posted by Home quick-action to switch to the Watchtower tab.
    static let vaultSwitchToWatchtower = Notification.Name("vaultSwitchToWatchtower")
    /// Posted by the Spaces sheet to switch to the Items tab (spaces management).
    static let vaultSwitchToItems = Notification.Name("vaultSwitchToItems")
}
