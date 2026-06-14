import SwiftUI

/// Manage folders ("Spaces"): reorder, create, edit, delete. Pushed from Home.
struct ManageFoldersScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var editorFolder: Folder?
    @State private var creating = false

    var body: some View {
        List {
            if env.repository.folders.isEmpty {
                ContentUnavailableView {
                    Label { Text("No Spaces yet") } icon: { PolarisIcon(Icons.folder, size: 40) }
                } description: {
                    Text("Group your items by company, project, or context.")
                }
            } else {
                ForEach(env.repository.folders) { folder in
                    Button { editorFolder = folder } label: {
                        HStack(spacing: 12) {
                            FolderBadge(icon: folder.iconAsset, color: folder.color, size: 34)
                            Text(folder.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(env.repository.itemCount(for: folder.id))").foregroundStyle(.secondary)
                            PolarisIcon(Icons.chevronRight, size: 14).foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .onMove(perform: move)
            }
        }
        .themedFormBackground()
        .navigationTitle("Spaces")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { creating = true } label: { PolarisIcon(Icons.add, size: 24) }
            }
            if !env.repository.folders.isEmpty {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
        }
        .sheet(isPresented: $creating) { FolderEditorSheet(folder: nil) }
        .sheet(item: $editorFolder) { FolderEditorSheet(folder: $0) }
    }

    /// Persist the new order as sequential `sortIndex` values.
    private func move(from source: IndexSet, to destination: Int) {
        var ordered = env.repository.folders
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, folder) in ordered.enumerated() where folder.sortIndex != index {
            var updated = folder
            updated.sortIndex = index
            try? env.repository.updateFolder(updated)
        }
    }
}
