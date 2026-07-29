import SwiftUI

/// Read-only item view (1Password-style): favicon/badge header, a rounded card
/// of tap-to-copy fields, trash, and metadata. Looks the item up live so it
/// reflects edits.
struct ItemDetailScreen: View {
    let itemID: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    // Compact-iOS UIKit shell: a navigator-pushed detail cannot be popped by
    // SwiftUI `dismiss()` — the nested NavigationStack root swallows it — so pop
    // the shell's UINavigationController instead. A nested push / modal / the
    // iPad-Mac sidebar (isNavigatorRoot == false) keeps using `dismiss()`.
    @Environment(AppNavigator.self) private var navigator: AppNavigator?
    @Environment(\.isNavigatorRoot) private var isNavigatorRoot
    @State private var editing: EditorTarget?
    @State private var confirmTrash = false
    @State private var confirmDelete = false
    @State private var showLocatedIn = false
    @State private var showLastIdentityBlock = false
    @State private var showShareAccess = false
    @State fileprivate var confirmLeave = false
    @State fileprivate var leaveError: String?
    /// Server refused the leave — offer the device-local removal instead.
    @State fileprivate var offerLocalRemoval = false
    /// Realtime-action offline notice (leaving needs iCloud to be true).
    @State fileprivate var showLeaveOfflineNotice = false
    /// Per-recipient management sheet (V1.2 follow-up: multi-recipient shares).
    @State private var selectedShare: ItemShareRecord?
    /// Resume stepper (design 12b/12c) for a recipient still pending.
    @State private var resumeShare: ItemShareRecord?
    /// Safety code for a shared item (optional out-of-band comparison).
    @State private var safetyCode: String?
    /// Optional safety-code comparison, opened from the card below. Never
    /// presented automatically.
    @State private var showVerifySheet = false
    /// "Send to Browser" (Loox Quick View) chooser sheet.
    @State private var showQuickViewChooser = false
    /// Non-nil when the entry is tapped but blocked (e.g. guard2-only item) —
    /// shown as an explainer rather than a silently disabled control.
    @State private var quickViewBlockedReason: String?
    /// True once the password row has scrolled past the top of the viewport —
    /// drives the T3 bottom "Copy Password" cluster's fade-in.
    @State private var passwordFieldOffscreen = false

    /// Message-style alert bindings, lifted out of `body` so the long modifier
    /// chain stays within the Swift type-checker's budget (a stable-Xcode build
    /// times out type-checking the inline two-closure `Binding`s otherwise).
    private var quickViewBlockedAlert: Binding<Bool> {
        Binding(get: { quickViewBlockedReason != nil },
                set: { if !$0 { quickViewBlockedReason = nil } })
    }

    fileprivate var leaveErrorAlert: Binding<Bool> {
        Binding(get: { leaveError != nil },
                set: { if !$0 { leaveError = nil } })
    }

    /// Named coordinate space for the scroll view, so the password row's frame
    /// (reported via `PasswordFieldFramePreferenceKey`) can be read relative to
    /// the viewport rather than the whole screen — no iOS-18-only scroll API.
    private static let scrollSpace = "itemDetailScroll"

    /// Owned items come from the vault store; `shared::` ids resolve to the
    /// recipient-side projection (read-only, V1.2).
    private var item: VaultItem? {
        env.repository.item(id: itemID) ?? env.sharedItems.item(id: itemID)
    }

    /// T3: the bottom "Copy Password" cluster only ever applies to an OWNED
    /// login item that actually has a password to copy. Shared projections are
    /// excluded outright: their values render only behind `SharedAccessGateView`
    /// (INV-01), and this overlay must not offer a copy path outside that gate.
    private func showsCopyPasswordCluster(_ item: VaultItem) -> Bool {
        // An extra-protected password is sealed ciphertext — the cluster would
        // copy the raw payload, bypassing the reveal gate.
        if item.passwordField?.isExtraProtected == true { return false }
        return item.sharedOrigin == nil
            && item.category == .login
            && !(item.passwordField?.value.isEmpty ?? true)
    }

    private func copyPassword(_ item: VaultItem) {
        guard let field = item.passwordField, !field.value.isEmpty, !field.isExtraProtected else { return }
        env.clipboard.copy(field.value, label: field.label, sensitive: true)
        env.repository.markUsed(item)
    }

    private func folder(for item: VaultItem) -> Folder? {
        item.folderId.flatMap { id in env.repository.folders.first { $0.id == id } }
    }

    /// Multi-layer entry gate (DEC-QV-EXPOSURE-01): the exposure/cohort
    /// resolver AND the capability's own availability must both allow it —
    /// an outage here must never surface, since Quick View is fully optional.
    private var quickViewEntryVisible: Bool {
        QuickViewExposureProvider.entryVisible(manifestExposure: env.capabilities.quickViewExposure)
            && env.capabilities.availability(.quickView, operation: .create) == .available
    }

    /// A guard2-only item (or one with nothing shareable at all) has no
    /// fields `LooxLinkEnvelope` will ever offer — the entry stays tappable
    /// but explains why instead of silently doing nothing.
    private func quickViewDisabledReason(for item: VaultItem) -> String? {
        guard LooxLinkEnvelope.shareableFields(of: item).isEmpty else { return nil }
        if item.fields.contains(where: { $0.isExtraProtected }) {
            return appString("This item's fields are behind Extra Protection, so nothing can be sent to a browser.")
        }
        return appString("This item has nothing to send to a browser yet.")
    }

    /// Close this detail after a mutation. On the compact-iOS shell a
    /// navigator-pushed root pops the UINavigationController; everywhere else
    /// (nested push, modal, sidebar) SwiftUI `dismiss()` already does the right
    /// thing.
    private func closeDetail() {
        if isNavigatorRoot, let navigator {
            navigator.pop()
        } else {
            dismiss()
        }
    }

    var body: some View {
        ScrollView {
            if let item {
                VStack(spacing: 18) {
                    header(item)
                    if item.sharedOrigin != nil { sharedBadge }
                    if item.sharedOrigin == nil {
                        fieldsCard(item)
                    } else {
                        // Shared VALUES render only after live authorization
                        // (INV-01) — header/title above are Tier-1 metadata.
                        // Nothing else stands between the user and a share
                        // they accepted: the sender was named at accept time,
                        // so re-interrogating them here would question a
                        // decision they already made.
                        SharedAccessGateView(itemID: item.id) { fieldsCard(item) }
                    }
                    // Tags read as footnotes to the content, so they follow the
                    // fields card instead of sitting between it and the title.
                    organization(item)
                    if item.sharedOrigin == nil {
                        ItemPasskeysSection(item: item)
                        sharingSection(item)
                    } else {
                        SharedItemPasskeysSection(itemID: item.id)
                        safetyCodeSection
                    }
                    // Progressive disclosure: a live owned item shows no destructive
                    // card here at all (Move to Trash lives in the "…" menu). Trashed
                    // items keep Restore/Delete; shared projections keep Leave Share.
                    if item.isTrashed || item.sharedOrigin != nil {
                        trashCard(item)
                    }
                    metadata(item)
                }
                .padding(Space.gutter)
                // Reserve room so the floating "Copy Password" cluster (T3) never
                // covers the metadata row for a login item that could show it.
                .padding(.bottom, showsCopyPasswordCluster(item) ? Metric.controlLarge + Space.s7 : 0)
            } else if itemID.hasPrefix("shared::") && !env.sharedItems.hasLoaded {
                // Cold-start restore straight into a shared item: the
                // projection is still loading — don't flash "not found".
                ProgressView().frame(maxWidth: .infinity)
                    .padding(.top, Space.s10 + Space.s9 + Space.s2)
            } else {
                ContentUnavailableView {
                    Label { Text("Item not found") } icon: { VaultIcon(Icons.alert, size: Metric.iconTileLarge) }
                }
                .padding(.top, Space.s9 + Space.s7)
            }
        }
        .coordinateSpace(name: Self.scrollSpace)
        .onPreferenceChange(PasswordFieldFramePreferenceKey.self) { frame in
            // The row's bottom edge has scrolled above the viewport's top edge —
            // fail-closed to "on screen" (hidden cluster) if the row hasn't
            // reported a frame yet (e.g. no password field / not laid out).
            passwordFieldOffscreen = frame != .zero && frame.maxY <= 0
        }
        .overlay(alignment: .bottom) {
            if let item, showsCopyPasswordCluster(item) {
                BottomCopyPasswordCluster(visible: passwordFieldOffscreen) {
                    copyPassword(item)
                }
            }
        }
        // Grouped (gray) page background so the white surface cards read as cards — like Home.
        // `appBackground` uses the plain background, which equals the card color in light mode
        // (both white), making the cards invisible.
        .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
        // No nav-bar title — the big title in the header below is the item's identity.
        .navigationTitle("")
        .platformNavigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let item, item.sharedOrigin == nil {
                // ONE share button (V5): sharing access IS the share action.
                // The plain website-URL ShareLink lives in the "…" menu.
                // Trashed items aren't shareable — restore first.
                if !item.isTrashed {
                    ToolbarItem(placement: .platformPrimaryAction) {
                        Button { showShareAccess = true } label: {
                            VaultIcon(Icons.share, size: Metric.iconInline)
                        }
                    }
                }
                ToolbarItem(placement: .platformPrimaryAction) {
                    Menu {
                        Button { editing = .edit(item) } label: { Label { Text("Edit") } icon: { VaultIcon(Icons.edit) } }
                            .accessibilityIdentifier("item.detail.edit")
                        // Pin + favorite moved here from beside the Space pill —
                        // the pill (Space + identity) needs the whole line.
                        Button { env.repository.togglePin(item) } label: {
                            Label(item.pinned ? "Unpin" : "Pin",
                                  image: item.pinned ? Icons.pinFill : Icons.pin)
                        }
                        Button { try? env.repository.toggleFavorite(item) } label: {
                            Label(item.favorite ? "Unfavorite" : "Favorite",
                                  image: item.favorite ? Icons.starFill : Icons.star)
                        }
                        if quickViewEntryVisible {
                            Button {
                                if let reason = quickViewDisabledReason(for: item) {
                                    quickViewBlockedReason = reason
                                } else {
                                    showQuickViewChooser = true
                                }
                            } label: { Label { Text("Send to Browser") } icon: { VaultIcon("ic_globe") } }
                        }
                        if let url = item.urlField?.value, !url.isEmpty {
                            ShareLink(item: url) {
                                Label { Text("Share Website Link") } icon: { VaultIcon(Icons.share) }
                            }
                        }
                        // Archiving only applies to live items; a trashed item is
                        // restored/deleted from the card below instead.
                        if !item.isTrashed {
                            if item.archived {
                                Button { env.repository.unarchive(item) } label: { Label { Text("Unarchive") } icon: { VaultIcon(Icons.archive) } }
                            } else {
                                Button {
                                    if env.repository.identityRemovalGate(item) == .lastActiveIdentity {
                                        showLastIdentityBlock = true
                                    } else {
                                        env.repository.archive(item); closeDetail()
                                    }
                                } label: { Label { Text("Archive") } icon: { VaultIcon(Icons.archive) } }
                            }
                        }
                        // Progressive disclosure (T1): the only destructive action for a
                        // live item now lives here instead of an always-visible card —
                        // reuses the same confirm dialog + last-identity gate as before.
                        if !item.isTrashed {
                            Divider()
                            Button(role: .destructive) {
                                if env.repository.identityRemovalGate(item) == .lastActiveIdentity {
                                    showLastIdentityBlock = true
                                } else {
                                    confirmTrash = true
                                }
                            } label: { Label { Text("Move to Trash") } icon: { VaultIcon(Icons.trash) } }
                        }
                    } label: { VaultIcon("ic_menu_horizontal", size: Metric.iconInline) }
                        .accessibilityLabel(Text("More"))
                        .accessibilityIdentifier("item.detail.more")
                }
            } else if item?.sharedOrigin != nil {
                ToolbarItem(placement: .platformPrimaryAction) {
                    Menu {
                        Button(role: .destructive) { requestLeave() } label: {
                            Label { Text("Leave Share") } icon: { VaultIcon(Icons.trash) }
                        }
                    } label: { VaultIcon("ic_menu_horizontal", size: Metric.iconInline) }
                        .accessibilityLabel(Text("More"))
                }
            }
        }
        .sheet(item: $editing) { ItemEditorScreen(target: $0) }
        .sheet(isPresented: $showLocatedIn) { LocatedInSheet(itemID: itemID) }
        .sheet(isPresented: $showShareAccess) { ShareAccessSheet(itemID: itemID) }
        .sheet(isPresented: $showQuickViewChooser) {
            if let item {
                QuickViewEntryChooserSheet(
                    itemID: itemID,
                    defaultSelectedFieldIDs: LooxLinkEnvelope.defaultSelectedFieldIDs(of: item))
            }
        }
        .alert("Can't send to a browser", isPresented: quickViewBlockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: quickViewBlockedReason ?? "")
        }
        .sheet(isPresented: $showVerifySheet) {
            SafetyCodeVerifySheet(itemID: itemID) { decision in
                env.sharedItems.recordVerification(decision, forItem: itemID,
                                                   vaultKey: env.session.vaultKey?.bytes)
                showVerifySheet = false
            }
        }
        .sheet(item: $selectedShare) { ShareRecipientDetailSheet(share: $0) }
        .sheet(item: $resumeShare) { ShareResumeStepperSheet(share: $0) }
        .confirmationDialog("Move this item to Trash?", isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                Haptics.error()
                if let item { try? env.repository.moveToTrash(item); closeDetail() }
            }
        }
        .confirmationDialog("Permanently delete this item?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                Haptics.error()
                if let item { try? env.repository.delete(item); closeDetail() }
            }
        } message: {
            Text("This can’t be undone.")
        }
        .alert("Keep at least one identity", isPresented: $showLastIdentityBlock) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This is your only identity. Add another before removing this one.")
        }
        .modifier(LeaveShareDialogs(screen: self))
        // A shared item that vanished (revoked while away, or after the
        // projection finished loading) has no screen to show — go back.
        .task(id: env.sharedItems.hasLoaded ? "loaded" : "loading") {
            if itemID.hasPrefix("shared::"), env.sharedItems.hasLoaded,
               env.sharedItems.item(id: itemID) == nil {
                closeDetail()
            }
        }
        // Safety code loads once per shared item (needs the unlocked Vault Key).
        .task(id: itemID) {
            guard item?.sharedOrigin != nil,
                  let vaultKey = env.session.vaultKey?.bytes else { return }
            safetyCode = await env.sharedItems.safetyCode(forItem: itemID, vaultKey: vaultKey)
        }
        .onAppear {
            if let item { AnalyticsEngine.shared.log(.itemViewed(item.category)) }
        }
        // The Extra Password unlock is scoped to THIS visit: leaving the item
        // reseals every level2 field, so coming back always asks again. Sheets
        // presented over the screen (protect, reveal, editor) don't trigger
        // this — only actually navigating away does.
        .onDisappear { env.session.clearLevel2Key() }
    }

    /// Gate before the confirm dialog: leaving is only real once iCloud says
    /// so — offline, the tap explains instead of walking into a CloudKit error.
    private func requestLeave() {
        if env.reachability.hasSatisfiedNetworkPath {
            confirmLeave = true
        } else {
            Haptics.warning()
            showLeaveOfflineNotice = true
        }
    }

    fileprivate func leaveShare() async {
        guard let vaultKey = env.session.vaultKey?.bytes else { return }
        do {
            try await env.sharedItems.leave(itemId: itemID, vaultKey: vaultKey)
            closeDetail()
        } catch {
            // Connection dropped between the gate and the operation: the
            // friendly explanation, never the raw CloudKit error text.
            if !env.reachability.hasSatisfiedNetworkPath {
                leaveError = appString("You need an internet connection to leave a share. You still have access until then.")
            } else {
                // The server refused, and no wording of a retry can change
                // that: the owner may be gone, or the zone stranded by an
                // older build. Offer the local exit instead of a dead end —
                // a raw CloudKit string here is both unreadable and useless.
                ShareDiagnostics.log("LEAVE", "server refused: \(error)")
                offerLocalRemoval = true
            }
        }
    }

    /// Last resort when the server will not release the share. Honest in the
    /// dialog about what it cannot do: participation is untouched, so the owner
    /// still sees this account and the same invite would bring the item back.
    fileprivate func removeShareLocally() async {
        guard let vaultKey = env.session.vaultKey?.bytes else { return }
        await env.sharedItems.forgetLocally(itemId: itemID, vaultKey: vaultKey)
        closeDetail()
    }

    /// Persist a single field change (e.g. protect / remove protection).
    private func update(_ field: DynamicField, in item: VaultItem) {
        guard let index = item.fields.firstIndex(where: { $0.id == field.id }) else { return }
        var updated = item
        updated.fields[index] = field
        try? env.repository.update(updated)
    }

    /// Remove a field (e.g. a deleted attachment) and persist.
    private func remove(_ field: DynamicField, in item: VaultItem) {
        var updated = item
        updated.fields.removeAll { $0.id == field.id }
        try? env.repository.update(updated)
    }

    /// Non-secret text for the Share button: the website URL if present, else the title.
    private func shareText(_ item: VaultItem) -> String {
        if let url = item.urlField?.value, !url.isEmpty { return url }
        return item.title.isEmpty ? appString("Untitled") : item.title
    }

    private func header(_ item: VaultItem) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Space pill + pin/favorite share one row, so the controls sit at the Space row's
            // vertical center. Tap the pill → "Located In" sheet (move / view Space).
            HStack(spacing: Space.s3) {
                if item.sharedOrigin != nil {
                    // Shared projections live in no Space and take no pins —
                    // a static origin pill replaces the Located-In button.
                    HStack(spacing: Space.s2) {
                        VaultIcon(Icons.share, size: 13).themedForeground(.accentText)
                        Text("Shared with Me").vaultType(.subhead).themedForeground(.secondary)
                    }
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(VaultColors.surface,
                                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    Spacer(minLength: 8)
                } else {
                    // Space + owning identity in one pill. Pin/favorite moved to
                    // the header "…" menu — this line can run long (two names)
                    // and side controls would crowd it into truncation.
                    Button { showLocatedIn = true } label: {
                        HStack(spacing: Space.s2) {
                            SpaceIdentityLine(folder: folder(for: item))
                            VaultIcon(Icons.chevronDown, size: 11).themedForeground(.secondary)
                        }
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .background(VaultColors.surface,
                                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: Space.s3) {
                // One avatar for every case: brand app-icon, then (auto style) the
                // website favicon, else the type / monogram / custom avatar.
                FaviconView(urlString: item.urlField?.value, category: item.category, size: 56,
                            title: item.title, iconAsset: item.iconAsset)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .vaultType(.screenTitle).lineLimit(1).truncationMode(.tail)
                        .accessibilityIdentifier("item.detail.title")
                    Text(item.category.title).vaultType(.subhead).themedForeground(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Space.s1)
    }

    /// Item tags, below the fields card. Accent-soft pills — hashtags carry the
    /// link color the way they do everywhere else on the internet; the white
    /// pill made them read as plain metadata.
    @ViewBuilder private func organization(_ item: VaultItem) -> some View {
        if !item.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    ForEach(item.tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            VaultIcon(Icons.hashtag, size: 11)
                                .foregroundStyle(Color(rgb: env.theme.active.accentText))
                            Text(tag).vaultType(.subhead)
                                .foregroundStyle(Color(rgb: env.theme.active.accentText))
                        }
                        // Matches `FilterChip`'s pill padding (Space.s3/s2) for a
                        // consistent chip language across the app.
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .background(Color(rgb: env.theme.active.accentSoft), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fieldsCard(_ item: VaultItem) -> some View {
        let fields = item.fields.filter { !$0.isEmpty }
        // Item's 2FA secret (if any) so the Large Type viewer can float the live
        // code — handy when typing the password for a site that also needs 2FA.
        let totpSecret = item.totpField?.value
        let isShared = item.sharedOrigin != nil
        // askEachTime TOTP capabilities render as Request controls — the
        // secret never left the owner's vault, so there is no code to show.
        let requestFieldIds: [String] = isShared
            ? (env.sharedItems.grant(forItem: item.id)?.capabilities
                .filter { $0.value.isAskEachTimeTOTP }.keys.sorted() ?? [])
            : []
        return VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                Group {
                    if isShared {
                        // Read-only: mutation affordances hidden, reveal/copy stay.
                        DetailFieldRow(field: field, category: item.category, readOnly: true)
                    } else {
                        DetailFieldRow(field: field,
                                       category: item.category,
                                       totpSecret: field.kind == .totp ? nil : totpSecret,
                                       onChange: { update($0, in: item) },
                                       onRemove: { remove(field, in: item) },
                                       onUsed: { env.repository.markUsed(item) })
                    }
                }
                // Reports the password row's on-screen position (T3 bottom cluster) —
                // no-op for every other field kind.
                .background {
                    if field.kind == .password {
                        GeometryReader { proxy in
                            Color.clear.preference(key: PasswordFieldFramePreferenceKey.self,
                                                    value: proxy.frame(in: .named(Self.scrollSpace)))
                        }
                    }
                }
                if index < fields.count - 1 || !requestFieldIds.isEmpty {
                    Divider().padding(.leading, Space.s4)
                }
            }
            ForEach(Array(requestFieldIds.enumerated()), id: \.element) { index, fieldId in
                if let model = env.sharedItems.requestModel(forItem: item.id, fieldId: fieldId) {
                    // Same header treatment as every other detail field row —
                    // this IS the item's TOTP field, just owner-gated.
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Verification code")
                            .vaultType(.caption).fontWeight(.medium)
                            .foregroundStyle(env.theme.active.color(.accentText))
                        RequestCodeView(model: model, deviceId: env.sharedItems.recipientDeviceId)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s3)
                    if index < requestFieldIds.count - 1 {
                        Divider().padding(.leading, Space.s4)
                    }
                }
            }
        }
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
        // Elevation over hairline stroke — a true semantic card, but the shadow
        // alone separates it from the grouped background (card ≠ page in both
        // light and dark, see VaultColors.surface vs .groupedBackground).
        .elevation(.level1)
    }

    /// Origin banner for a shared projection (read-only semantics up front) — a
    /// flat tinted banner, not another stroked card competing with the fields card.
    private var sharedBadge: some View {
        VaultInfoBanner(.info, icon: Icons.shield,
                         text: "Shared with you. You can use what's listed here, but not edit it.")
    }

    /// Optional out-of-band check, always available and never in the way. The
    /// code copies from here so it can be sent over whatever channel the two
    /// people already use, and the footnote says what the current decision
    /// actually bought — including the one case that still holds content back
    /// from AutoFill, so a withheld share explains itself instead of silently
    /// never appearing there.
    @ViewBuilder private var safetyCodeSection: some View {
        if let safetyCode {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .top, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text("Safety code").vaultType(.sectionLabel).themedForeground(.secondary)
                        Text(verbatim: safetyCode)
                            .font(.vaultCode(size: 17))
                            .monospacedDigit()
                            .themedForeground()
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: Space.s2)
                    Button {
                        // ClipboardService owns the confirmation haptic.
                        env.clipboard.copy(safetyCode, label: appString("Safety code"),
                                           sensitive: false)
                    } label: {
                        VaultIcon(Icons.copy, size: Metric.iconInline)
                            .themedForeground(.accentText)
                            .frame(width: Metric.hitMin, height: Metric.hitMin)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Copy code"))
                }
                Text(safetyCodeExplanation)
                    .vaultType(.footnote).themedForeground(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showVerifySheet = true } label: {
                    Text("Compare safety code")
                        .vaultType(.body).fontWeight(.medium)
                        .themedForeground(.accentText)
                        .frame(maxWidth: .infinity, minHeight: Metric.hitMin, alignment: .leading)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VaultColors.surface)
            .vaultCornerRadius(Radius.md)
        }
    }

    /// What the recorded decision means for this share, in the user's terms.
    private var safetyCodeExplanation: LocalizedStringKey {
        switch env.sharedItems.verification(forItem: itemID) {
        case .confirmed:
            return "You confirmed this code with the owner."
        case .pending:
            return "AutoFill will not offer this share until you decide about it here."
        case .accepted, .skipped:
            return "Compare with the code on the owner's device to verify the connection."
        }
    }

    /// Owner side (V4/design 12b): who this item is shared with. Active
    /// recipients open the management sheet; a pending recipient's row
    /// carries its own mini 4-segment progress + a Resume badge that opens
    /// the same stepper sheet Home/Notifications use — one canonical resume
    /// surface no matter the entry point.
    @ViewBuilder private func sharingSection(_ item: VaultItem) -> some View {
        let shares = env.sharingStore.shares(forItem: item.id)
        if !shares.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Shared with").vaultType(.sectionLabel).themedForeground(.tertiary)
                VStack(spacing: 0) {
                    ForEach(shares) { share in
                        shareRow(share)
                        Divider().padding(.leading, Space.s4)
                    }
                    // In-flow entry to add another recipient — the toolbar share
                    // icon stays, but sharing again from where the recipients
                    // already live is the natural next tap.
                    if !item.isTrashed {
                        Button { showShareAccess = true } label: {
                            HStack(spacing: Space.s3) {
                                VaultIcon(Icons.addCircle, size: Metric.iconInline)
                                    .themedForeground(.accentText)
                                Text("Share this item")
                                    .vaultType(.body)
                                    .foregroundStyle(env.theme.uiTint)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Space.s4).padding(.vertical, 12)
                            .frame(minHeight: Metric.hitMin)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(VaultColors.surface)
                .vaultCornerRadius(Radius.md)
                .elevation(.level1)
            }
        }
    }

    private func shareRow(_ share: ItemShareRecord) -> some View {
        let isPending = share.status != .active
        return Button {
            if isPending { resumeShare = share } else { selectedShare = share }
        } label: {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s3) {
                    VaultIcon(Icons.share, size: Metric.iconInline)
                        .themedForeground(isPending ? .warning : .accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: share.recipientLabel)
                            .vaultType(.body).themedForeground()
                            .lineLimit(1).truncationMode(.middle)
                        Text(ShareStepper.detailSubtitle(for: share.status).inAppLocalized)
                            .vaultType(.footnote).themedForeground(isPending ? .warning : .success)
                    }
                    Spacer(minLength: Space.s2)
                    if isPending {
                        VaultStatusBadge(kind: .action, label: "Resume")
                    } else {
                        // No status badge here: the subtitle already says the
                        // share is active — the duplicate pill only squeezed
                        // the recipient's email into an ellipsis.
                        VaultIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
                    }
                }
                if isPending {
                    ShareMiniProgressBar(status: share.status)
                        .padding(.leading, Metric.iconInline + Space.s3)
                }
            }
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Destructive-action card: rendered ONLY for a trashed item (Restore/Delete) or a
    /// shared projection (Leave Share). A live owned item has no card here at all —
    /// "Move to Trash" moved into the "…" menu (progressive disclosure; Archive lives
    /// there too, so this avoided a second destructive card competing for attention).
    @ViewBuilder
    private func trashCard(_ item: VaultItem) -> some View {
        if item.sharedOrigin != nil {
            // Shared projection: the only destructive action is leaving —
            // a realtime CloudKit operation, so it dims while offline and the
            // tap explains instead of throwing a raw iCloud error.
            actionRow("Leave Share", icon: Icons.trash,
                      color: env.theme.active.color(.destructive)) {
                requestLeave()
            }
            .onlineActionAppearance(online: env.reachability.hasSatisfiedNetworkPath)
        } else if item.isTrashed {
            VStack(spacing: Space.s3) {
                actionRow("Restore", icon: Icons.refresh, color: env.theme.active.color(.success)) {
                    try? env.repository.restore(item); closeDetail()
                }
                actionRow("Delete Permanently", icon: Icons.delete, color: env.theme.active.color(.destructive)) {
                    confirmDelete = true
                }
            }
        }
    }

    private func actionRow(_ label: LocalizedStringKey, icon: String, color: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s3) {
                VaultIcon(icon, size: Metric.iconInline).foregroundStyle(color)
                Text(label).vaultType(.body).foregroundStyle(color)
                Spacer()
            }
            .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VaultColors.surface,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .elevation(.level1)
        }
        .buttonStyle(.plain)
    }

    /// Single compact metadata line — two rows of near-identical low-priority
    /// text read as noise; one line reads as a caption.
    private func metadata(_ item: VaultItem) -> some View {
        let created = item.createdAt.formatted(date: .abbreviated, time: .shortened)
        let modified = item.updatedAt.formatted(date: .abbreviated, time: .shortened)
        return Text(appString("Created \(created), modified \(modified)"))
            .vaultType(.caption).themedForeground(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.s1)
    }
}


/// The leave-a-share dialog group, lifted out of `ItemDetailScreen.body`.
///
/// Not a stylistic split: `body` on this screen carries enough chained
/// modifiers that adding the local-removal dialog tipped Swift's expression
/// type-checker past its time budget and the file stopped compiling. Each
/// dialog stays exactly what it was.
private struct LeaveShareDialogs: ViewModifier {
    let screen: ItemDetailScreen

    func body(content: Content) -> some View {
        content
            .alert("Couldn't leave the share", isPresented: screen.leaveErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: screen.leaveError ?? "")
            }
            .confirmationDialog("Remove it from this iPhone?",
                                isPresented: screen.$offerLocalRemoval,
                                titleVisibility: .visible) {
                Button("Remove From This iPhone", role: .destructive) {
                    Task { await screen.removeShareLocally() }
                }
            } message: {
                Text("iCloud would not release this share, so it can only be removed here. The owner still has you on their list, and accepting their invite again would bring it back.")
            }
            .confirmationDialog("Leave this share?", isPresented: screen.$confirmLeave,
                                titleVisibility: .visible) {
                Button("Leave Share", role: .destructive) {
                    Haptics.error()
                    Task { await screen.leaveShare() }
                }
            } message: {
                Text("You'll lose access to it. The owner can share with you again later.")
            }
            .offlineActionNotice(isPresented: screen.$showLeaveOfflineNotice,
                                 message: "You need an internet connection to leave a share. You still have access until then.")
    }
}
