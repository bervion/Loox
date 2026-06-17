import SwiftUI

/// Home header: folder-filter switcher (dot + name + chevron) on the left,
/// Add and Settings icon buttons on the right. Tapping the switcher presents
/// a FolderPickerSheet variant that filters the whole Home screen.
struct HomeHeaderBar: View {
    /// nil = "All spaces" (no folder filter).
    @Binding var selectedFolderId: String?
    let onAdd: () -> Void
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
        HStack(spacing: Space.s2) {
            // Folder switcher — tapping opens the picker sheet.
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

                    PolarisIcon(Icons.chevronDown, size: 17)
                        .themedForeground(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Spacer()

            // Add item
            Button(action: onAdd) {
                PolarisIcon(Icons.add, size: Metric.iconUtility)
                    .foregroundStyle(env.theme.active.color(.accent))
            }
            .frame(width: Metric.hitMin, height: Metric.hitMin)
            .accessibilityLabel(Text("Add Item"))

            // Settings
            Button(action: onSettings) {
                PolarisIcon(Icons.settings, size: Metric.iconUtility)
                    .foregroundStyle(env.theme.active.color(.accent))
            }
            .frame(width: Metric.hitMin, height: Metric.hitMin)
            .accessibilityLabel(Text("Settings"))
        }
        .padding(.horizontal, Space.gutter)
        .frame(minHeight: Metric.hitMin)
        .sheet(isPresented: $showFolderPicker) {
            HomeFolderPickerSheet(selectedFolderId: $selectedFolderId)
        }
    }
}

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
