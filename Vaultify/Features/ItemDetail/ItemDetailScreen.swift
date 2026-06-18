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
    @State private var showLocatedIn = false

    private var item: VaultItem? { env.repository.item(id: itemID) }

    private func folder(for item: VaultItem) -> Folder? {
        item.folderId.flatMap { id in env.repository.folders.first { $0.id == id } }
    }

    var body: some View {
        ScrollView {
            if let item {
                VStack(spacing: 18) {
                    header(item)
                    organization(item)
                    fieldsCard(item)
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
        .appBackground()
        .navigationTitle(item?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let item {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editing = .edit(item) } label: { Label("Edit", image: Icons.edit) }
                        if item.archived {
                            Button { env.repository.unarchive(item) } label: { Label("Unarchive", image: Icons.archive) }
                        } else {
                            Button { env.repository.archive(item); dismiss() } label: { Label("Archive", image: Icons.archive) }
                        }
                    } label: { PolarisIcon("ic_menu_horizontal", size: Metric.iconInline) }
                }
            }
        }
        .sheet(item: $editing) { ItemEditorScreen(target: $0) }
        .sheet(isPresented: $showLocatedIn) { LocatedInSheet(itemID: itemID) }
        .confirmationDialog("Move this item to Trash?", isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                if let item { try? env.repository.moveToTrash(item); dismiss() }
            }
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

    private func header(_ item: VaultItem) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            // Space pill (left-aligned) → tap opens the "Located In" sheet (move / view Space).
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

            HStack(spacing: Space.s3) {
                // Favicon wins when the item has a website; otherwise the custom icon / avatar.
                if let url = item.urlField?.value, !url.isEmpty {
                    FaviconView(urlString: url, category: item.category, size: 56)
                } else {
                    ItemThumbnail(title: item.title, category: item.category,
                                  iconAsset: item.iconAsset, size: 56)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .font(.title2.bold()).lineLimit(2)
                    Text(item.category.title).font(.subheadline).themedForeground(.secondary)
                }
                Spacer(minLength: 8)
                Button { env.repository.togglePin(item) } label: {
                    PolarisIcon(item.pinned ? Icons.pinFill : Icons.pin, size: 22)
                        .foregroundStyle(item.pinned ? env.theme.active.color(.accent) : env.theme.active.color(.secondary))
                }
                .buttonStyle(.plain)
                Button { try? env.repository.toggleFavorite(item) } label: {
                    PolarisIcon(item.favorite ? Icons.starFill : Icons.star, size: Metric.iconUtility)
                        .foregroundStyle(item.favorite ? VaultColors.strengthMedium : env.theme.active.color(.secondary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Space.s1)
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
        return VStack(spacing: 0) {
            ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                DetailFieldRow(field: field,
                               onChange: { update($0, in: item) },
                               onRemove: { remove(field, in: item) },
                               onUsed: { env.repository.markUsed(item) })
                if index < fields.count - 1 { Divider().padding(.leading, Space.gutter) }
            }
        }
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }

    private func trashCard(_ item: VaultItem) -> some View {
        Button(role: .destructive) { confirmTrash = true } label: {
            HStack(spacing: 12) {
                PolarisIcon(Icons.trash, size: Metric.iconInline).foregroundStyle(env.theme.active.color(.destructive))
                Text("Move to Trash").foregroundStyle(env.theme.active.color(.destructive))
                Spacer()
            }
            .padding(.horizontal, Space.gutter).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VaultColors.surface,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
