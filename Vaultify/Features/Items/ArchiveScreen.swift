import SwiftUI

/// Archived items — kept out of normal lists but not deleted. Swipe to unarchive
/// or move to Recently Deleted.
struct ArchiveScreen: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.repository.archived.isEmpty {
                ContentUnavailableView {
                    Label { Text("No archived items") } icon: { VaultIcon(Icons.archive, size: 44) }
                } description: {
                    Text("Archived items are hidden from your lists but never deleted.")
                }
            } else {
                List {
                    ForEach(env.repository.archived) { item in
                        NavigationLink(value: item.id) { VaultItemRow(item: item) }
                            .swipeActions(edge: .leading) {
                                Button { env.repository.unarchive(item) } label: {
                                    Label { Text("Unarchive") } icon: { VaultIcon(Icons.archive) }
                                }
                                .tint(VaultColors.strengthStrong)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { try? env.repository.moveToTrash(item) } label: {
                                    Label { Text("Trash") } icon: { VaultIcon(Icons.trash) }
                                }
                            }
                            .listRowBackground(VaultColors.surface)
                    }
                }
            }
        }
        .themedFormBackground()
        .navigationTitle("Archive")
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}
