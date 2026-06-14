import SwiftUI

/// The "Spaces" section on Home. Shown only when there are **2+ spaces** — a
/// single space needs no chooser, so it stays hidden (manage it via
/// Settings → Spaces). Create/manage live behind the "…" menu in the header.
struct SpacesSection: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var path: NavigationPath
    @State private var creating = false
    @State private var editFolder: Folder?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    var body: some View {
        if env.repository.folders.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                header
                grid
            }
            .sheet(isPresented: $creating) { FolderEditorSheet(folder: nil) }
            .sheet(item: $editFolder) { FolderEditorSheet(folder: $0) }
        }
    }

    private var header: some View {
        HStack {
            Text("Spaces").font(.title3.bold())
            Spacer()
            Menu {
                Button { creating = true } label: { Label("Create Space", image: Icons.addCircle) }
                Button { path.append(VaultRoute.manageFolders) } label: { Label("Manage Spaces", image: Icons.edit) }
            } label: {
                PolarisIcon("ic_menu_horizontal", size: 22)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(env.repository.folders) { folder in
                Button { path.append(VaultRoute.folder(folder.id)) } label: {
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
        }
    }

    private var unfiledCard: some View {
        Button { path.append(VaultRoute.folder(nil)) } label: {
            SpaceCard(name: nil, icon: Icons.folder, color: .gray, count: env.repository.unfiledCount)
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
