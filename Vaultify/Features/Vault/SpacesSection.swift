import SwiftUI

/// The "Spaces" section on Home: a grid of folder cards (+ Unfiled + Add), with
/// a header that links to manage. Empty state offers creating the first Space.
struct SpacesSection: View {
    @Environment(AppEnvironment.self) private var env
    @State private var creating = false
    @State private var editFolder: Folder?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if env.repository.folders.isEmpty {
                createFirstCard.padding(.horizontal, 16)
            } else {
                grid.padding(.horizontal, 16)
            }
        }
        .sheet(isPresented: $creating) { FolderEditorSheet(folder: nil) }
        .sheet(item: $editFolder) { FolderEditorSheet(folder: $0) }
    }

    private var header: some View {
        HStack {
            Text("Spaces").font(.title3.bold())
            Spacer()
            if !env.repository.folders.isEmpty {
                NavigationLink(value: VaultRoute.manageFolders) { Text("Manage").font(.subheadline) }
            }
        }
        .padding(.horizontal, 16)
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(env.repository.folders) { folder in
                NavigationLink(value: VaultRoute.folder(folder.id)) {
                    SpaceCard(name: folder.name, icon: folder.iconAsset,
                              color: folder.color, count: env.repository.itemCount(for: folder.id))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { editFolder = folder } label: { Label("Edit", image: Icons.edit) }
                    Button(role: .destructive) { try? env.repository.deleteFolder(folder) } label: {
                        Label("Delete", image: Icons.trash)
                    }
                }
            }
            if env.repository.unfiledCount > 0 { unfiledCard }
            addCard
        }
    }

    private var unfiledCard: some View {
        NavigationLink(value: VaultRoute.folder(nil)) {
            SpaceCard(name: nil, icon: Icons.folder, color: .gray, count: env.repository.unfiledCount)
        }
        .buttonStyle(.plain)
    }

    private var addCard: some View {
        Button { creating = true } label: {
            VStack(spacing: 8) {
                PolarisIcon(Icons.add, size: 22).foregroundStyle(.secondary)
                Text("Add Space").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [5]))
            )
        }
        .buttonStyle(.plain)
    }

    private var createFirstCard: some View {
        Button { creating = true } label: {
            HStack(spacing: 12) {
                FolderBadge(icon: "ic_folder", color: .blue, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create your first Space").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text("Group items by company or project").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                PolarisIcon(Icons.chevronRight, size: 14).foregroundStyle(.tertiary)
            }
            .padding(14).frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// One Space tile: badge + name + item count. A nil `name` renders the localized
/// "Unfiled" pseudo-folder.
private struct SpaceCard: View {
    let name: String?
    let icon: String
    let color: FolderColor
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FolderBadge(icon: icon, color: color, size: 38)
            Group {
                if let name { Text(name) } else { Text("Unfiled") }
            }
            .font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
