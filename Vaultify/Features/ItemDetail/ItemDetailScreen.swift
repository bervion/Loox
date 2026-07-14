import SwiftUI

/// Read-only item view (1Password-style): favicon/badge header, a rounded card
/// of tap-to-copy fields, trash, and metadata. Looks the item up live so it
/// reflects edits.
struct ItemDetailScreen: View {
    let itemID: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var editing: EditorTarget?
    @State private var confirmTrash = false
    @State private var confirmDelete = false
    @State private var showLocatedIn = false
    @State private var showLastIdentityBlock = false
    @State private var showShareAccess = false
    @State private var confirmLeave = false
    @State private var leaveError: String?
    /// Per-recipient management sheet (V1.2 follow-up: multi-recipient shares).
    @State private var selectedShare: ItemShareRecord?
    /// Resume stepper (design 12b/12c) for a recipient still pending.
    @State private var resumeShare: ItemShareRecord?
    /// Safety code for a shared item (optional out-of-band comparison).
    @State private var safetyCode: String?
    /// One-time trust interstitial for a shared item whose safety-code
    /// decision is still pending.
    @State private var showVerifySheet = false
    /// "Open on Computer" (Loox Quick View) chooser sheet.
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

    private var leaveErrorAlert: Binding<Bool> {
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
        item.sharedOrigin == nil
            && item.category == .login
            && !(item.passwordField?.value.isEmpty ?? true)
    }

    private func copyPassword(_ item: VaultItem) {
        guard let field = item.passwordField, !field.value.isEmpty else { return }
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

    var body: some View {
        ScrollView {
            if let item {
                VStack(spacing: 18) {
                    header(item)
                    if item.sharedOrigin != nil { sharedBadge }
                    organization(item)
                    if item.sharedOrigin == nil {
                        fieldsCard(item)
                    } else if needsVerification(item) {
                        // The one-time trust decision comes before any use:
                        // value rows (and request controls inside them) are
                        // not even built until the user confirms the safety
                        // code or explicitly skips — dismissing the sheet
                        // decides nothing and this card re-prompts.
                        verifyPromptCard
                    } else {
                        // Shared VALUES render only after live authorization
                        // (INV-01) — header/title above are Tier-1 metadata.
                        SharedAccessGateView(itemID: item.id) { fieldsCard(item) }
                    }
                    if item.sharedOrigin == nil {
                        ItemPasskeysSection(item: item)
                        sharingSection(item)
                    } else {
                        SharedItemPasskeysSection(itemID: item.id)
                        // Manual re-check surface for decided shares; while
                        // pending, the interstitial is the code's one home.
                        if !needsVerification(item) { safetyCodeCard }
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
                    Label { Text("Item not found") } icon: { PolarisIcon(Icons.alert, size: Metric.iconTileLarge) }
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
                            PolarisIcon(Icons.share, size: Metric.iconInline)
                        }
                    }
                }
                ToolbarItem(placement: .platformPrimaryAction) {
                    Menu {
                        Button { editing = .edit(item) } label: { Label("Edit", image: Icons.edit) }
                        if quickViewEntryVisible {
                            Button {
                                if let reason = quickViewDisabledReason(for: item) {
                                    quickViewBlockedReason = reason
                                } else {
                                    showQuickViewChooser = true
                                }
                            } label: { Label("Open on Computer", image: "ic_globe") }
                        }
                        if let url = item.urlField?.value, !url.isEmpty {
                            ShareLink(item: url) {
                                Label("Share Website Link", image: Icons.share)
                            }
                        }
                        // Archiving only applies to live items; a trashed item is
                        // restored/deleted from the card below instead.
                        if !item.isTrashed {
                            if item.archived {
                                Button { env.repository.unarchive(item) } label: { Label("Unarchive", image: Icons.archive) }
                            } else {
                                Button {
                                    if env.repository.identityRemovalGate(item) == .lastActiveIdentity {
                                        showLastIdentityBlock = true
                                    } else {
                                        env.repository.archive(item); dismiss()
                                    }
                                } label: { Label("Archive", image: Icons.archive) }
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
                            } label: { Label("Move to Trash", image: Icons.trash) }
                        }
                    } label: { PolarisIcon("ic_menu_horizontal", size: Metric.iconInline) }
                }
            } else if item?.sharedOrigin != nil {
                ToolbarItem(placement: .platformPrimaryAction) {
                    Menu {
                        Button(role: .destructive) { confirmLeave = true } label: {
                            Label("Leave Share", image: Icons.trash)
                        }
                    } label: { PolarisIcon("ic_menu_horizontal", size: Metric.iconInline) }
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
        .alert("Can't open on a computer", isPresented: quickViewBlockedAlert) {
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
                if let item { try? env.repository.moveToTrash(item); dismiss() }
            }
        }
        .confirmationDialog("Permanently delete this item?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                Haptics.error()
                if let item { try? env.repository.delete(item); dismiss() }
            }
        } message: {
            Text("This can’t be undone.")
        }
        .alert("Keep at least one identity", isPresented: $showLastIdentityBlock) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This is your only identity. Add another before removing this one.")
        }
        .alert("Couldn't leave the share", isPresented: leaveErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: leaveError ?? "")
        }
        .confirmationDialog("Leave this share?", isPresented: $confirmLeave,
                            titleVisibility: .visible) {
            Button("Leave Share", role: .destructive) {
                Haptics.error()
                Task { await leaveShare() }
            }
        } message: {
            Text("You'll lose access to it. The owner can share with you again later.")
        }
        // A shared item that vanished (revoked while away, or after the
        // projection finished loading) has no screen to show — go back.
        .task(id: env.sharedItems.hasLoaded ? "loaded" : "loading") {
            if itemID.hasPrefix("shared::"), env.sharedItems.hasLoaded,
               env.sharedItems.item(id: itemID) == nil {
                dismiss()
            }
        }
        // Safety code loads once per shared item (needs the unlocked Vault Key).
        .task(id: itemID) {
            guard item?.sharedOrigin != nil,
                  let vaultKey = env.session.vaultKey?.bytes else { return }
            safetyCode = await env.sharedItems.safetyCode(forItem: itemID, vaultKey: vaultKey)
        }
    }

    private func leaveShare() async {
        guard let vaultKey = env.session.vaultKey?.bytes else { return }
        do {
            try await env.sharedItems.leave(itemId: itemID, vaultKey: vaultKey)
            dismiss()
        } catch {
            // Swallowing this reads as "the button does nothing" — say why.
            leaveError = error.localizedDescription
        }
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
                        PolarisIcon(Icons.share, size: 13).themedForeground(.accentText)
                        Text("Shared with Me").vaultType(.subhead).themedForeground(.secondary)
                    }
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(VaultColors.surface,
                                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    Spacer(minLength: 8)
                } else {
                    Button { showLocatedIn = true } label: {
                        HStack(spacing: Space.s2) {
                            if let folder = folder(for: item) {
                                FolderBadge(icon: folder.iconAsset, color: folder.color, size: 20)
                                Text(folder.name)
                                    .vaultType(.subhead).fontWeight(.semibold).themedForeground()
                                    .lineLimit(1).truncationMode(.tail)
                            } else {
                                Text("No Space").vaultType(.subhead).themedForeground(.secondary)
                            }
                            PolarisIcon(Icons.chevronDown, size: 11).themedForeground(.secondary)
                        }
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .background(VaultColors.surface,
                                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 8)

                    pinFavoriteControls(item)
                }
            }

            HStack(spacing: Space.s3) {
                // Brand items always get the app-icon avatar (matching Home — without this
                // a "Loox Account" with no website fell to the letter thumbnail); then the
                // favicon when the item has a website; otherwise the custom icon / avatar.
                if LooxAppIcon.isBrandTitle(item.title) {
                    LooxAppIcon(size: 56)
                } else if let url = item.urlField?.value, !url.isEmpty {
                    FaviconView(urlString: url, category: item.category, size: 56, title: item.title)
                } else {
                    ItemThumbnail(title: item.title, category: item.category,
                                  iconAsset: item.iconAsset, size: 56)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .vaultType(.screenTitle).lineLimit(1).truncationMode(.tail)
                    Text(item.category.title).vaultType(.subhead).themedForeground(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, Space.s1)
    }

    /// Pin + favorite toggles, grouped with spacing — shown at the Space row's vertical center.
    @ViewBuilder private func pinFavoriteControls(_ item: VaultItem) -> some View {
        HStack(spacing: Space.s4) {
            Button { env.repository.togglePin(item) } label: {
                PolarisIcon(item.pinned ? Icons.pinFill : Icons.pin, size: 22)
                    .foregroundStyle(item.pinned ? env.theme.active.color(.accentText) : env.theme.active.color(.secondary))
            }
            .buttonStyle(.plain)
            Button { try? env.repository.toggleFavorite(item) } label: {
                PolarisIcon(item.favorite ? Icons.starFill : Icons.star, size: Metric.iconUtility)
                    .foregroundStyle(item.favorite ? VaultColors.favoriteStar : env.theme.active.color(.secondary))
            }
            .buttonStyle(.plain)
        }
    }

    /// Item tags. The Space now lives in the header pill, so this is tags-only.
    @ViewBuilder private func organization(_ item: VaultItem) -> some View {
        if !item.tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s2) {
                    ForEach(item.tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            PolarisIcon(Icons.hashtag, size: 11).themedForeground(.secondary)
                            Text(tag).vaultType(.subhead)
                        }
                        // Matches `FilterChip`'s pill padding (Space.s3/s2) for a
                        // consistent chip language across the app.
                        .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                        .background(VaultColors.surface, in: Capsule())
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
                        RequestCodeView(model: model, deviceId: env.sharedItems.recipientDeviceId,
                                        verificationPending: needsVerification(item),
                                        onVerificationRequired: { showVerifySheet = true })
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

    /// True while the recipient has not yet confirmed or explicitly skipped
    /// the safety-code compare for this share. Tier-0 items (device not
    /// authorized) keep their own gate message instead — there is no
    /// content a decision could unlock. Reads the Keychain-backed marker
    /// live; deciding in the sheet triggers a re-render via sheet state.
    private func needsVerification(_ item: VaultItem) -> Bool {
        guard let origin = item.sharedOrigin, origin.deviceAuthorized else { return false }
        return env.sharedItems.verification(forItem: item.id) == .pending
    }

    /// Interstitial entry card shown in place of the value rows while the
    /// trust decision is pending.
    private var verifyPromptCard: some View {
        VStack(spacing: Space.s3) {
            PolarisIcon(Icons.shield, size: Metric.iconTile).themedForeground(.accent)
            Text("Check the safety code with the owner before you use this shared item.")
                .vaultType(.callout).themedForeground(.secondary)
                .multilineTextAlignment(.center)
            Button { showVerifySheet = true } label: {
                Text("Verify this share").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s6)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.lg)
        .elevation(.level1)
    }

    /// Origin banner for a shared projection (read-only semantics up front) — a
    /// flat tinted banner, not another stroked card competing with the fields card.
    private var sharedBadge: some View {
        VaultInfoBanner(.info, icon: Icons.shield,
                         text: "Shared with you. You can use what's listed here, but not edit it.")
    }

    /// Discreet verification affordance — matches the code on the owner's
    /// activation screen (optional out-of-band comparison).
    @ViewBuilder private var safetyCodeCard: some View {
        if let safetyCode {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Safety code").vaultType(.sectionLabel).themedForeground(.secondary)
                Text(verbatim: safetyCode)
                    .font(.vaultCode(size: 17))
                    .monospacedDigit()
                    .themedForeground()
                Text("Compare with the code on the owner's device to verify the connection.")
                    .vaultType(.footnote).themedForeground(.secondary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VaultColors.surface)
            .vaultCornerRadius(Radius.md)
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
                                PolarisIcon(Icons.addCircle, size: Metric.iconInline)
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
                    PolarisIcon(Icons.share, size: Metric.iconInline)
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
                        PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
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
            // Shared projection: the only destructive action is leaving.
            actionRow("Leave Share", icon: Icons.trash,
                      color: env.theme.active.color(.destructive)) {
                confirmLeave = true
            }
        } else if item.isTrashed {
            VStack(spacing: Space.s3) {
                actionRow("Restore", icon: Icons.refresh, color: env.theme.active.color(.success)) {
                    try? env.repository.restore(item); dismiss()
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
                PolarisIcon(icon, size: Metric.iconInline).foregroundStyle(color)
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
