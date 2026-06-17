import SwiftUI

/// Items tab: the organization browser — Spaces (with a Create Space row),
/// Categories, Tags, plus standalone Archive and Recently Deleted rows.
struct ItemsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var path = NavigationPath()
    @State private var creatingSpace = false

    private var categories: [ItemCategory] {
        ItemCategory.allCases.filter { env.repository.count(forCategory: $0) > 0 }
    }
    private var tags: [(tag: String, count: Int)] { env.repository.allTags() }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                spacesSection
                if !categories.isEmpty { categoriesSection }
                if !tags.isEmpty { tagsSection }
                Section {
                    standaloneRow(Text("Archive"), icon: Icons.archive,
                                  count: env.repository.archived.count, route: .archive)
                    standaloneRow(Text("Recently Deleted"), icon: Icons.trash,
                                  count: env.repository.trashed.count, route: .recentlyDeleted)
                }
                .listRowBackground(VaultColors.surface)
            }
            .listStyle(.insetGrouped)
            // Align the grouped cards' leading edge with the large title gutter.
            .contentMargins(.horizontal, Space.gutter, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.background))
            .navigationTitle("Items")
            .vaultNavigationDestinations()
            .sheet(isPresented: $creatingSpace) { FolderEditorSheet(folder: nil) }
        }
    }

    private var spacesSection: some View {
        Section("Spaces") {
            ForEach(env.repository.folders) { folder in
                NavigationLink(value: VaultRoute.folder(folder.id)) {
                    HStack(spacing: Space.s3) {
                        FolderBadge(icon: folder.iconAsset, color: folder.color, size: 30)
                        Text(folder.name)
                        Spacer()
                        Text("\(env.repository.itemCount(for: folder.id))").themedForeground(.secondary)
                    }
                }
            }
            if env.repository.unfiledCount > 0 {
                NavigationLink(value: VaultRoute.folder(nil)) {
                    HStack(spacing: Space.s3) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(VaultColors.fill).frame(width: 30, height: 30)
                            .overlay(PolarisIcon(Icons.folder, size: 16).themedForeground(.secondary))
                        Text("Unfiled")
                        Spacer()
                        Text("\(env.repository.unfiledCount)").themedForeground(.secondary)
                    }
                }
            }
            Button { creatingSpace = true } label: {
                Label { Text("Create Space") } icon: { PolarisIcon(Icons.addCircle) }
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    private var categoriesSection: some View {
        Section("Categories") {
            ForEach(categories) { category in
                NavigationLink(value: VaultRoute.category(category)) {
                    HStack(spacing: Space.s3) {
                        leadingTile(category.iconAsset,
                                    fill: Color(rgb: env.theme.active.accent).opacity(0.14),
                                    iconColor: Color(rgb: env.theme.active.accent),
                                    iconSize: 17)
                        Text(category.title)
                        Spacer()
                        Text("\(env.repository.count(forCategory: category))").themedForeground(.secondary)
                    }
                }
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    private var tagsSection: some View {
        Section("Tags") {
            ForEach(tags, id: \.tag) { entry in
                NavigationLink(value: VaultRoute.tag(entry.tag)) {
                    HStack(spacing: Space.s3) {
                        leadingTile(Icons.hashtag, fill: VaultColors.fill,
                                    iconColor: env.theme.active.color(.iconSecondary), iconSize: 16)
                        Text(entry.tag)
                        Spacer()
                        Text("\(entry.count)").themedForeground(.secondary)
                    }
                }
            }
        }
        .listRowBackground(VaultColors.surface)
    }

    private func standaloneRow(_ title: Text, icon: String, count: Int, route: VaultRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Space.s3) {
                leadingTile(icon, fill: VaultColors.fill,
                            iconColor: env.theme.active.color(.iconSecondary), iconSize: 16)
                title
                Spacer()
                if count > 0 { Text("\(count)").themedForeground(.secondary) }
            }
        }
    }

    /// 30pt rounded leading badge (matches the Spaces folder tiles) so every row
    /// has a consistent tinted icon tile instead of a bare glyph.
    private func leadingTile(_ icon: String, fill: Color, iconColor: Color, iconSize: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .frame(width: 30, height: 30)
            .overlay(PolarisIcon(icon, size: iconSize).foregroundStyle(iconColor))
    }
}
