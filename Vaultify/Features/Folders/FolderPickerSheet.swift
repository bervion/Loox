import SwiftUI

/// Pick the folder ("Space") an item belongs to: Unfiled (None), an existing
/// folder, or create a new one inline. Binds the item's `folderId`.
struct FolderPickerSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Binding var folderId: String?
    @State private var creating = false

    var body: some View {
        VaultSheetScaffold(
            // Own key, NOT "Space": that key doubles as the password generator's
            // separator-character label, whose VI is "Khoảng trắng" (whitespace) —
            // this sheet's title rendered as that in Vietnamese.
            title: "Choose a Space",
            leading: { EmptyView() },
            trailing: { SheetDismissButton("Done") }
        ) {
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
                                row(name: Text(verbatim: folder.displayName),
                                    badge: FolderBadge(icon: folder.iconAsset, color: folder.color, size: Metric.badgeTile),
                                    selected: folderId == folder.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(VaultColors.surface)
                }
                Section {
                    Button { creating = true } label: {
                        Label { Text("New Space…") } icon: { VaultIcon(Icons.addCircle) }
                    }
                    .buttonStyle(.plain)
                }
                .listRowBackground(VaultColors.surface)
            }
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
        HStack(spacing: Space.s3) {
            if let badge {
                badge
            } else {
                // Same proportional formula as FolderBadge at this size, so the "None" placeholder
                // tile is provably consistent with every real folder badge, not just visually close.
                RoundedRectangle(cornerRadius: Metric.badgeTile * 0.28, style: .continuous)
                    .fill(VaultColors.fill).frame(width: Metric.badgeTile, height: Metric.badgeTile)
            }
            name.themedForeground()
            Spacer()
            if selected { VaultIcon(Icons.check, size: 18).foregroundStyle(Color(rgb: env.theme.active.accent)) }
        }
        .contentShape(.rect)
    }
}
