import SwiftUI

/// "Located In" sheet shown from the detail header: which Space the item lives in, with a
/// Move action (only when there are ≥2 Spaces to move between). Looks the item up live so the
/// row reflects a move immediately.
struct LocatedInSheet: View {
    let itemID: String
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var showMovePicker = false

    private var item: VaultItem? { env.repository.item(id: itemID) }
    private var folder: Folder? {
        item?.folderId.flatMap { id in env.repository.folders.first { $0.id == id } }
    }
    private var canMove: Bool { env.repository.folders.count >= 2 }

    var body: some View {
        VaultSheetScaffold(title: "Located In",
                           leading: { EmptyView() },
                           trailing: { SheetDismissButton("Done") }) {
            Form {
                Section {
                    HStack(spacing: Space.s3) {
                        if let folder {
                            FolderBadge(icon: folder.iconAsset, color: folder.color, size: 30)
                            Text(folder.name).themedForeground()
                        } else {
                            // Proportional radius matching FolderBadge/CategoryBadge's
                            // `size * 0.28` sibling convention at the same 30pt tile size.
                            RoundedRectangle(cornerRadius: 30 * 0.28, style: .continuous)
                                .fill(VaultColors.fill).frame(width: 30, height: 30)
                            Text("No Space").themedForeground(.secondary)
                        }
                        Spacer()
                        if canMove {
                            Button { showMovePicker = true } label: {
                                Label { Text("Move") } icon: { PolarisIcon(Icons.enter) }
                                    .vaultType(.subhead).fontWeight(.medium)
                            }
                            .buttonStyle(.bordered)
                            .tint(env.theme.active.color(.accent))
                        }
                    }
                }
                .listRowBackground(VaultColors.surface)
            }
            .sheet(isPresented: $showMovePicker) {
                FolderPickerSheet(folderId: Binding(
                    get: { item?.folderId },
                    set: { moveItem(to: $0) }
                ))
            }
        }
    }

    private func moveItem(to folderId: String?) {
        guard var updated = item else { return }
        updated.folderId = folderId
        try? env.repository.update(updated)
    }
}
