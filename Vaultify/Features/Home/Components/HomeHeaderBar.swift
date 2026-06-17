import SwiftUI

/// Home header: folder-switcher title on the left (plain, no glass pill) +
/// glass action cluster on the right (search · add · settings).
///
/// Composes `VaultScreenHeader` so the overlay positioning, padding, and glass
/// logic all live in one shared place.
struct HomeHeaderBar: View {
    /// nil = "All Spaces" (no folder filter).
    @Binding var selectedFolderId: String?
    /// Called with the chosen item category when the user picks from the Add menu.
    let onAddCategory: (ItemCategory) -> Void
    let onSettings: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var showFolderPicker = false

    private var selectedFolder: Folder? {
        guard let id = selectedFolderId else { return nil }
        return env.repository.folders.first { $0.id == id }
    }

    private var folderDisplayName: String {
        selectedFolder?.name ?? appString("All Spaces")
    }

    private var folderDotColor: Color {
        selectedFolder?.color.tint ?? env.theme.active.color(.iconSecondary)
    }

    var body: some View {
        VaultScreenHeader(
            leading: {
                // Plain button — the title is NOT wrapped in a glass pill;
                // only the right cluster receives the glass treatment.
                Button {
                    showFolderPicker = true
                } label: {
                    HStack(spacing: Space.s2) {
                        Circle()
                            .fill(folderDotColor)
                            .frame(width: 10, height: 10)

                        Text(folderDisplayName)
                            .vaultType(.screenTitle)
                            .themedForeground()
                            .lineLimit(1)

                        PolarisIcon(Icons.chevronDown, size: 15)
                            .themedForeground(.secondary)
                    }
                    .padding(.trailing, Space.s1)
                    .frame(minHeight: Metric.hitMin)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            },
            trailing: {
                HeaderActionCluster {
                    // Search — switches to the Search tab via notification
                    HeaderIconButton(
                        Icons.search,
                        accessibilityLabel: "Search"
                    ) {
                        NotificationCenter.default.post(name: .vaultSwitchToSearch, object: nil)
                    }

                    // Add — menu to choose item type
                    Menu {
                        ForEach(ItemCategory.allCases) { category in
                            Button {
                                onAddCategory(category)
                            } label: {
                                Label {
                                    Text(category.title)
                                } icon: {
                                    PolarisIcon(category.iconAsset)
                                }
                            }
                        }
                    } label: {
                        PolarisIcon(Icons.pageAdd, size: Metric.iconUtility)
                            .themedForeground()
                    }
                    .frame(width: Metric.hitMin, height: Metric.hitMin)
                    .accessibilityLabel(Text("Add Item"))

                    // Settings — direct, no "more" indirection
                    HeaderIconButton(
                        Icons.settings,
                        accessibilityLabel: "Settings"
                    ) {
                        onSettings()
                    }
                }
            }
        )
        .sheet(isPresented: $showFolderPicker) {
            HomeFolderPickerSheet(selectedFolderId: $selectedFolderId)
        }
    }
}

// MARK: - Folder picker sheet

/// Lightweight folder picker for the Home header. Lets the user pick "All
/// Spaces" (nil) or a specific folder to filter the Home feed.
private struct HomeFolderPickerSheet: View {
    @Binding var selectedFolderId: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    folderRow(
                        name: Text("All Spaces"),
                        badge: nil,
                        selected: selectedFolderId == nil
                    ) { select(nil) }
                }
                .listRowBackground(VaultColors.surface)

                if !env.repository.folders.isEmpty {
                    Section {
                        ForEach(env.repository.folders) { folder in
                            folderRow(
                                name: Text(folder.name),
                                badge: FolderBadge(icon: folder.iconAsset,
                                                   color: folder.color,
                                                   size: 30),
                                selected: selectedFolderId == folder.id
                            ) { select(folder.id) }
                        }
                    }
                    .listRowBackground(VaultColors.surface)
                }
            }
            .themedFormBackground()
            .navigationTitle(Text("Spaces"))
            .themedColorScheme()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func select(_ id: String?) {
        selectedFolderId = id
        dismiss()
    }

    @ViewBuilder
    private func folderRow(name: Text,
                           badge: FolderBadge?,
                           selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let badge {
                    badge
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(VaultColors.fill)
                        .frame(width: 30, height: 30)
                }
                name.themedForeground()
                Spacer()
                if selected {
                    PolarisIcon(Icons.check, size: 18)
                        .foregroundStyle(Color(rgb: env.theme.active.accent))
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
