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
    /// Safety code for a shared item (optional out-of-band comparison).
    @State private var safetyCode: String?

    /// Owned items come from the vault store; `shared::` ids resolve to the
    /// recipient-side projection (read-only, V1.2).
    private var item: VaultItem? {
        env.repository.item(id: itemID) ?? env.sharedItems.item(id: itemID)
    }

    private func folder(for item: VaultItem) -> Folder? {
        item.folderId.flatMap { id in env.repository.folders.first { $0.id == id } }
    }

    var body: some View {
        ScrollView {
            if let item {
                VStack(spacing: 18) {
                    header(item)
                    if item.sharedOrigin != nil { sharedBadge }
                    organization(item)
                    fieldsCard(item)
                    if item.sharedOrigin == nil {
                        ItemPasskeysSection(item: item)
                        sharingSection(item)
                    } else {
                        safetyCodeCard
                    }
                    trashCard(item)
                    metadata(item)
                }
                .padding(Space.gutter)
            } else {
                ContentUnavailableView {
                    Label { Text("Item not found") } icon: { PolarisIcon(Icons.alert, size: Metric.iconTileLarge) }
                }
                .padding(.top, 80)
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
                ToolbarItem(placement: .platformPrimaryAction) {
                    Button { showShareAccess = true } label: {
                        PolarisIcon(Icons.share, size: Metric.iconInline)
                    }
                }
                ToolbarItem(placement: .platformPrimaryAction) {
                    Menu {
                        Button { editing = .edit(item) } label: { Label("Edit", image: Icons.edit) }
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
        .confirmationDialog("Move this item to Trash?", isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let item { try? env.repository.moveToTrash(item); dismiss() }
            }
        }
        .confirmationDialog("Permanently delete this item?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
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
        .confirmationDialog("Leave this share?", isPresented: $confirmLeave,
                            titleVisibility: .visible) {
            Button("Leave Share", role: .destructive) {
                Task { await leaveShare() }
            }
        } message: {
            Text("You'll lose access to it. The owner can share with you again later.")
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
        try? await env.sharedItems.leave(itemId: itemID, vaultKey: vaultKey)
        dismiss()
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
                        PolarisIcon(Icons.share, size: 13).themedForeground(.accent)
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
                // Favicon wins when the item has a website; otherwise the custom icon / avatar.
                if let url = item.urlField?.value, !url.isEmpty {
                    FaviconView(urlString: url, category: item.category, size: 56, title: item.title)
                } else {
                    ItemThumbnail(title: item.title, category: item.category,
                                  iconAsset: item.iconAsset, size: 56)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .font(.title2.bold()).lineLimit(1).truncationMode(.tail)
                    Text(item.category.title).font(.subheadline).themedForeground(.secondary)
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
                    .foregroundStyle(item.pinned ? env.theme.active.color(.accent) : env.theme.active.color(.secondary))
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
                HStack(spacing: 8) {
                    ForEach(item.tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            PolarisIcon(Icons.hashtag, size: 11).themedForeground(.secondary)
                            Text(tag).font(.subheadline)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
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
                if isShared {
                    // Read-only: default no-op change/remove handlers keep
                    // reveal/copy while mutations go nowhere.
                    DetailFieldRow(field: field)
                } else {
                    DetailFieldRow(field: field,
                                   totpSecret: field.kind == .totp ? nil : totpSecret,
                                   onChange: { update($0, in: item) },
                                   onRemove: { remove(field, in: item) },
                                   onUsed: { env.repository.markUsed(item) })
                }
                if index < fields.count - 1 || !requestFieldIds.isEmpty {
                    Divider().padding(.leading, Space.gutter)
                }
            }
            ForEach(Array(requestFieldIds.enumerated()), id: \.element) { index, fieldId in
                if let model = env.sharedItems.requestModel(forItem: item.id, fieldId: fieldId) {
                    RequestCodeView(model: model, deviceId: env.sharedItems.recipientDeviceId)
                        .padding(.horizontal, Space.gutter)
                        .padding(.vertical, Space.s3)
                    if index < requestFieldIds.count - 1 {
                        Divider().padding(.leading, Space.gutter)
                    }
                }
            }
        }
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5)
        )
    }

    /// Origin banner for a shared projection (read-only semantics up front).
    private var sharedBadge: some View {
        HStack(spacing: Space.s2) {
            PolarisIcon(Icons.shield, size: Metric.iconInline).themedForeground(.accent)
            Text("Shared with you — you can use what's listed here, but not edit it.")
                .vaultType(.footnote).themedForeground(.secondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
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

    /// Owner side (V4): who this item is shared with — tap manages/revokes.
    @ViewBuilder private func sharingSection(_ item: VaultItem) -> some View {
        let shares = env.sharingStore.shares(forItem: item.id)
        if !shares.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { index, share in
                    Button { showShareAccess = true } label: {
                        HStack(spacing: Space.s3) {
                            PolarisIcon(Icons.share, size: Metric.iconInline)
                                .themedForeground(.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: share.recipientLabel)
                                    .vaultType(.body).themedForeground()
                                    .lineLimit(1).truncationMode(.middle)
                                Text(share.fingerprintConfirmed ? "Active" : "Pending")
                                    .vaultType(.footnote).themedForeground(.secondary)
                            }
                            Spacer(minLength: Space.s2)
                            PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
                        }
                        .padding(.horizontal, Space.gutter).padding(.vertical, 12)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if index < shares.count - 1 { Divider().padding(.leading, Space.gutter) }
                }
            }
            .background(VaultColors.surface)
            .vaultCornerRadius(Radius.md)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5)
            )
        }
    }

    /// Trashed items can be restored or purged; live items can be moved to Trash.
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
        } else {
            actionRow("Move to Trash", icon: Icons.trash, color: env.theme.active.color(.destructive)) {
                if env.repository.identityRemovalGate(item) == .lastActiveIdentity {
                    showLastIdentityBlock = true
                } else {
                    confirmTrash = true
                }
            }
        }
    }

    private func actionRow(_ label: LocalizedStringKey, icon: String, color: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PolarisIcon(icon, size: Metric.iconInline).foregroundStyle(color)
                Text(label).foregroundStyle(color)
                Spacer()
            }
            .padding(.horizontal, Space.gutter).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VaultColors.surface,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func metadata(_ item: VaultItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Created \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Text("Modified \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        .font(.caption).themedForeground(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.s1)
    }
}
