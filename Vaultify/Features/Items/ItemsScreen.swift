import SwiftUI

/// Items tab: the organization browser — Spaces (with a Create Space row),
/// Categories, Tags, plus standalone Archive and Recently Deleted rows.
///
/// Uses the same custom large-title + gutter layout as Home (ScrollView + grouped
/// cards at `Space.gutter`) so the title and the cards share one leading edge,
/// instead of `insetGrouped` whose cards sit further in than the large title.
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
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s6) {
                    spacesSection
                    if !categories.isEmpty { categoriesSection }
                    if !tags.isEmpty { tagsSection }
                    standaloneSection
                }
                .padding(.horizontal, Space.gutter)
                .padding(.top, Space.s2)
                .padding(.bottom, TabBarMetric.contentBottomInset)
            }
            .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
            .navigationTitle("Items")
            .navigationBarTitleDisplayMode(.large)
            .vaultNavigationDestinations()
            .sheet(isPresented: $creatingSpace) { FolderEditorSheet(folder: nil) }
        }
    }

    // MARK: Sections

    private var spacesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("Spaces")
            groupedCard {
                ForEach(env.repository.folders) { folder in
                    navRow(.folder(folder.id), title: Text(verbatim: folder.name),
                           count: env.repository.itemCount(for: folder.id), showDivider: true) {
                        FolderBadge(icon: folder.iconAsset, color: folder.color, size: 30)
                    }
                }
                if env.repository.unfiledCount > 0 {
                    navRow(.folder(nil), title: Text("Unfiled"),
                           count: env.repository.unfiledCount, showDivider: true) {
                        leadingTile(Icons.folder, fill: VaultColors.fill,
                                    iconColor: env.theme.active.color(.iconSecondary), iconSize: 16)
                    }
                }
                createSpaceRow
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("Categories")
            groupedCard {
                ForEach(Array(categories.enumerated()), id: \.element.id) { idx, category in
                    navRow(.category(category), title: Text(category.title),
                           count: env.repository.count(forCategory: category),
                           showDivider: idx < categories.count - 1) {
                        leadingTile(category.iconAsset,
                                    fill: Color(rgb: env.theme.active.accent).opacity(0.14),
                                    iconColor: Color(rgb: env.theme.active.accent), iconSize: 17)
                    }
                }
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("Tags")
            groupedCard {
                ForEach(Array(tags.enumerated()), id: \.element.tag) { idx, entry in
                    navRow(.tag(entry.tag), title: Text(verbatim: entry.tag),
                           count: entry.count, showDivider: idx < tags.count - 1) {
                        leadingTile(Icons.hashtag, fill: VaultColors.fill,
                                    iconColor: env.theme.active.color(.iconSecondary), iconSize: 16)
                    }
                }
            }
        }
    }

    private var standaloneSection: some View {
        groupedCard {
            navRow(.archive, title: Text("Archive"),
                   count: env.repository.archived.count, showDivider: true) {
                leadingTile(Icons.archive, fill: VaultColors.fill,
                            iconColor: env.theme.active.color(.iconSecondary), iconSize: 16)
            }
            navRow(.recentlyDeleted, title: Text("Recently Deleted"),
                   count: env.repository.trashed.count, showDivider: false) {
                leadingTile(Icons.trash, fill: VaultColors.fill,
                            iconColor: env.theme.active.color(.iconSecondary), iconSize: 16)
            }
        }
    }

    private var createSpaceRow: some View {
        Button { creatingSpace = true } label: {
            HStack(spacing: Space.s3) {
                PolarisIcon(Icons.addCircle, size: 22)
                    .foregroundStyle(Color(rgb: env.theme.active.accent))
                    .frame(width: 30)
                Text("Create Space").foregroundStyle(Color(rgb: env.theme.active.accent))
                Spacer()
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Row + container helpers (mirror Home)

    private func sectionHeader(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .vaultType(.sectionLabel)
            .themedForeground(.tertiary)
            .padding(.bottom, Space.s1)
    }

    @ViewBuilder
    private func groupedCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color(rgb: env.theme.active.elevatedBackground))
            .vaultCornerRadius(Radius.lg)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5)
            )
    }

    /// Navigation row inside a grouped card: leading badge + title + optional count
    /// + chevron, with a leading-inset hairline divider (matches the Home item rows).
    @ViewBuilder
    private func navRow<Leading: View>(
        _ route: VaultRoute,
        title: Text,
        count: Int,
        showDivider: Bool,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Space.s3) {
                leading()
                title.themedForeground()
                Spacer(minLength: Space.s2)
                if count > 0 {
                    Text("\(count)").themedForeground(.secondary)
                }
                PolarisIcon(Icons.chevronRight, size: 14).themedForeground(.tertiary)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(minHeight: Metric.rowHeight)
            .contentShape(.rect)
            .overlay(alignment: .bottom) {
                if showDivider {
                    Rectangle()
                        .fill(Color(rgb: env.theme.active.separator))
                        .frame(height: 0.5)
                        .padding(.leading, Space.s4 + 30 + Space.s3)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// 30pt rounded leading badge so every row has a consistent tinted icon tile.
    private func leadingTile(_ icon: String, fill: Color, iconColor: Color, iconSize: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .frame(width: 30, height: 30)
            .overlay(PolarisIcon(icon, size: iconSize).foregroundStyle(iconColor))
    }
}
