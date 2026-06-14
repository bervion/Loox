import SwiftUI

/// Trashed items: restore or permanently delete. Pushed from the Vault tab.
struct TrashScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmEmpty = false

    var body: some View {
        Group {
            if env.repository.trashed.isEmpty {
                ContentUnavailableView {
                    Label { Text("Trash is empty") } icon: { PolarisIcon(Icons.trash, size: 44) }
                } description: {
                    Text("Items you trash appear here until permanently deleted.")
                }
            } else {
                List {
                    Section {
                        Text("Items in Trash are still encrypted. Deleting them is permanent.")
                            .font(.footnote).themedForeground(.secondary)
                    }
                    .listRowBackground(VaultColors.surface)
                    ForEach(env.repository.trashed) { item in
                        VaultItemRow(item: item)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { try? env.repository.delete(item) } label: {
                                    Label("Delete", image: Icons.delete)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button { try? env.repository.restore(item) } label: {
                                    Label("Restore", image: Icons.refresh)
                                }
                                .tint(VaultColors.strengthStrong)
                            }
                            .listRowBackground(VaultColors.surface)
                    }
                }
            }
        }
        .themedFormBackground()
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !env.repository.trashed.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Empty", role: .destructive) { confirmEmpty = true }
                }
            }
        }
        .confirmationDialog("Permanently delete all trashed items?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) { try? env.repository.emptyTrash() }
        }
    }
}
