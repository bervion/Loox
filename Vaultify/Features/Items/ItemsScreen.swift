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
            }
            .listStyle(.insetGrouped)
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
                    HStack(spacing: 12) {
                        FolderBadge(icon: folder.iconAsset, color: folder.color, size: 30)
                        Text(folder.name)
                        Spacer()
                        Text("\(env.repository.itemCount(for: folder.id))").foregroundStyle(.secondary)
                    }
                }
            }
            if env.repository.unfiledCount > 0 {
                NavigationLink(value: VaultRoute.folder(nil)) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(VaultColors.fill).frame(width: 30, height: 30)
                            .overlay(PolarisIcon(Icons.folder, size: 16).foregroundStyle(.secondary))
                        Text("Unfiled")
                        Spacer()
                        Text("\(env.repository.unfiledCount)").foregroundStyle(.secondary)
                    }
                }
            }
            Button { creatingSpace = true } label: {
                Label { Text("Create Space") } icon: { PolarisIcon(Icons.addCircle) }
            }
        }
    }

    private var categoriesSection: some View {
        Section("Categories") {
            ForEach(categories) { category in
                NavigationLink(value: VaultRoute.category(category)) {
                    HStack(spacing: 12) {
                        PolarisIcon(category.iconAsset, size: 22)
                            .foregroundStyle(Color.accentColor).frame(width: 30)
                        Text(category.title)
                        Spacer()
                        Text("\(env.repository.count(forCategory: category))").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            ForEach(tags, id: \.tag) { entry in
                NavigationLink(value: VaultRoute.tag(entry.tag)) {
                    HStack(spacing: 12) {
                        PolarisIcon(Icons.hashtag, size: 18).foregroundStyle(.secondary).frame(width: 30)
                        Text(entry.tag)
                        Spacer()
                        Text("\(entry.count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func standaloneRow(_ title: Text, icon: String, count: Int, route: VaultRoute) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                PolarisIcon(icon, size: 20).foregroundStyle(.secondary).frame(width: 30)
                title
                Spacer()
                if count > 0 { Text("\(count)").foregroundStyle(.secondary) }
            }
        }
    }
}
