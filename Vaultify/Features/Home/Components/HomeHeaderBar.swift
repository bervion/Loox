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
    let onProfile: () -> Void

    @Environment(AppEnvironment.self) private var env
    @State private var showFolderPicker = false

    /// Circular avatar button → Profile. Shows the default identity's avatar (or its
    /// letter-avatar), falling back to a person glyph when no identity exists yet.
    @ViewBuilder private var profileButton: some View {
        Button(action: onProfile) {
            Group {
                if let identity = env.repository.defaultIdentity {
                    if let image = env.repository.avatarImage(for: identity.id) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ItemThumbnail(title: identity.title, category: .identity, iconAsset: nil, size: 28)
                    }
                } else {
                    PolarisIcon(Icons.person, size: Metric.iconUtility).themedForeground()
                }
            }
            .frame(width: 28, height: 28)
            .clipShape(Circle())
            .frame(width: Metric.hitMin, height: Metric.hitMin)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Profile"))
    }

    private var selectedFolder: Folder? {
        guard let id = selectedFolderId else { return nil }
        return env.repository.folders.first { $0.id == id }
    }

    /// Title shown in the header. A selected folder's name is verbatim (user data);
    /// the "All Spaces" fallback is a SwiftUI `Text` literal so it localizes via the
    /// environment locale (the in-app language) — `appString` can't switch the string
    /// table when the device language differs from the in-app choice.
    private var folderTitle: Text {
        if let folder = selectedFolder { return Text(verbatim: folder.name) }
        return Text("All Spaces")
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

                        folderTitle
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
                    // Profile — default identity avatar
                    profileButton

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
                        // Frame + contentShape inside the label so the full 44pt
                        // area triggers the menu, not just the 24pt glyph.
                        PolarisIcon(Icons.pageAdd, size: Metric.iconUtility)
                            .themedForeground()
                            .frame(width: Metric.hitMin, height: Metric.hitMin)
                            .contentShape(.rect)
                    }
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

/// Folder picker for the Home header. Lets the user pick "All Spaces" (nil) or a
/// specific folder to filter the Home feed, plus create/manage spaces.
private struct HomeFolderPickerSheet: View {
    @Binding var selectedFolderId: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var creatingSpace = false

    private var accent: Color { Color(rgb: env.theme.active.accent) }

    var body: some View {
        VaultSheetScaffold(
            title: "Spaces",
            trailing: {
                Button { creatingSpace = true } label: {
                    PolarisIcon(Icons.add, size: 18)
                }
                .accessibilityLabel(Text("Create New Space"))
            }
        ) {
            List {
                // Spaces — All Spaces + every folder, with item counts.
                Section {
                    spaceRow(name: Text("All Spaces"),
                             count: env.repository.allItems(folder: nil).count,
                             selected: selectedFolderId == nil) {
                        tile(Icons.inventory, fill: VaultColors.fill,
                             iconColor: env.theme.active.color(.iconSecondary))
                    } action: { select(nil) }

                    ForEach(env.repository.folders) { folder in
                        spaceRow(name: Text(verbatim: folder.name),
                                 count: env.repository.itemCount(for: folder.id),
                                 selected: selectedFolderId == folder.id) {
                            FolderBadge(icon: folder.iconAsset, color: folder.color, size: 30)
                        } action: { select(folder.id) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                // Management — create a space, or jump to the Items tab to manage them.
                Section {
                    managementRow(title: Text("Create New Space"),
                                  tint: accent, showChevron: false) {
                        tile(Icons.addCircle, fill: accent.opacity(0.14), iconColor: accent)
                    } action: { creatingSpace = true }

                    managementRow(title: Text("Manage Spaces & Members"),
                                  tint: nil, showChevron: true) {
                        tile(Icons.settings, fill: VaultColors.fill,
                             iconColor: env.theme.active.color(.iconSecondary))
                    } action: { openManagement() }
                }
                .listRowBackground(VaultColors.surface)
            }
            .sheet(isPresented: $creatingSpace) { FolderEditorSheet(folder: nil) }
        }
    }

    private func select(_ id: String?) {
        selectedFolderId = id
        dismiss()
    }

    /// Dismiss and switch to the Items tab — the surface that manages all spaces.
    private func openManagement() {
        dismiss()
        NotificationCenter.default.post(name: .vaultSwitchToItems, object: nil)
    }

    // MARK: Rows

    @ViewBuilder
    private func spaceRow<Leading: View>(
        name: Text, count: Int, selected: Bool,
        @ViewBuilder leading: () -> Leading,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading()
                name.themedForeground()
                Spacer(minLength: Space.s2)
                Text("\(count)").themedForeground(.secondary)
                if selected {
                    PolarisIcon(Icons.checkCircle, size: 20).foregroundStyle(accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func managementRow<Leading: View>(
        title: Text, tint: Color?, showChevron: Bool,
        @ViewBuilder leading: () -> Leading,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                leading()
                if let tint {
                    title.foregroundStyle(tint)
                } else {
                    title.themedForeground()
                }
                Spacer()
                if showChevron {
                    PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// 30pt rounded leading tile with a centred Polaris icon.
    private func tile(_ icon: String, fill: Color, iconColor: Color) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .frame(width: 30, height: 30)
            .overlay(PolarisIcon(icon, size: 17).foregroundStyle(iconColor))
    }
}
