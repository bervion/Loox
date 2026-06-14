import SwiftUI

/// Pick the folder ("Space") an item belongs to: Unfiled (None), an existing
/// folder, or create a new one inline. Binds the item's `folderId`.
struct FolderPickerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Binding var folderId: String?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { select(nil) } label: {
                        row(name: Text("None"), badge: nil, selected: folderId == nil)
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(VaultColors.surface)
                if !env.repository.folders.isEmpty {
                    Section {
                        ForEach(env.repository.folders) { folder in
                            Button { select(folder.id) } label: {
                                row(name: Text(folder.name),
                                    badge: FolderBadge(icon: folder.iconAsset, color: folder.color, size: 30),
                                    selected: folderId == folder.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(VaultColors.surface)
                }
                Section {
                    Button { creating = true } label: {
                        Label { Text("New Space…") } icon: { PolarisIcon(Icons.addCircle) }
                    }
                }
                .listRowBackground(VaultColors.surface)
            }
            .themedFormBackground()
            .navigationTitle("Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $creating) {
                FolderEditorSheet(folder: nil) { newID in folderId = newID }
            }
        }
    }

    private func select(_ id: String?) {
        folderId = id
        dismiss()
    }

    @ViewBuilder private func row(name: Text, badge: FolderBadge?, selected: Bool) -> some View {
        HStack(spacing: 12) {
            if let badge {
                badge
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(VaultColors.fill).frame(width: 30, height: 30)
            }
            name.themedForeground()
            Spacer()
            if selected { PolarisIcon(Icons.check, size: 18).foregroundStyle(Color.accentColor) }
        }
        .contentShape(.rect)
    }
}
