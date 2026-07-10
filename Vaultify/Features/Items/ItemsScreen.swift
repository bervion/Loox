import SwiftUI

/// Items tab: the organisation browser — Spaces (with a Create Space row),
/// Categories, Tags, plus standalone Archive and Recently Deleted rows.
///
/// Header floats over the scroll content as a glass overlay (same pattern as Home
/// and Watchtower) so the glass blurs whatever scrolls beneath it.
struct ItemsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(UIStateStore.self) private var uiState
    @State private var creatingSpace = false
    @State private var editorTarget: EditorTarget?
    @State private var scrolledUnder = false

    private var categories: [ItemCategory] {
        ItemCategory.allCases.filter { env.repository.count(forCategory: $0) > 0 }
    }
    private var tags: [(tag: String, count: Int)] { env.repository.allTags() }

    var body: some View {
        @Bindable var uiState = uiState
        return NavigationStack(path: $uiState.itemsPath) {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s6) {
                        // Top inset clears the floating header + reports scroll-edge state.
                        VaultHeaderScrollSpacer(scrolledUnder: $scrolledUnder)

                        spacesSection
                        if !categories.isEmpty { categoriesSection }
                        if !tags.isEmpty { tagsSection }
                        standaloneSection
                    }
                    .padding(.horizontal, Space.gutter)
                    .padding(.bottom, TabBarMetric.contentBottomInset)
                }
                .scrollIndicators(.hidden)

                // Floating header overlays scroll content — glass blurs beneath.
                VaultScreenHeader("Items") {
                    HeaderActionCluster {
                        // Add — menu to choose item type to create
                        Menu {
                            ForEach(ItemCategory.allCases) { category in
                                Button {
                                    editorTarget = .new(category)
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
                        // Plain glyph menu — macOS would otherwise draw a bordered pull-down button.
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)
                        .frame(width: Metric.hitMin, height: Metric.hitMin)
                        .accessibilityLabel(Text("Add Item"))
                    }
                }
            }
            .environment(\.vaultHeaderScrolledUnder, scrolledUnder)
            .background(Color(rgb: env.theme.active.groupedBackground).ignoresSafeArea())
            .platformHiddenNavigationBar()
            .vaultNavigationDestinations()
            .sheet(isPresented: $creatingSpace) { FolderEditorSheet(folder: nil) }
            .sheet(item: $editorTarget) { ItemEditorScreen(target: $0) }
        }
    }

    // MARK: - Sections

    private var spacesSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHeader("Spaces")
            groupedCard {
                ForEach(env.repository.activePersonaSpaces) { folder in
                    navRow(VaultRoute.folder(folder.id), title: Text(verbatim: folder.name),
                           count: env.repository.itemCount(for: folder.id), showDivider: true) {
                        FolderBadge(icon: folder.iconAsset, color: folder.color, size: Metric.badgeTile)
                    }
                }
                if env.repository.unfiledCount > 0 {
                    navRow(VaultRoute.folder(nil), title: Text("Unfiled"),
                           count: env.repository.unfiledCount, showDivider: true) {
                        leadingTile(Icons.folder, fill: VaultColors.fill,
                                    iconColor: env.theme.active.color(.iconSecondary), iconSize: 16)
                    }
                }
                // System space (U1): a projection over shares accepted from
                // other people — not a folder record, so no rename/delete.
                if env.settings.approvalModeEnabled || !env.sharedItems.items.isEmpty {
                    navRow(SharedWithMeRoute(), title: Text("Shared with Me"),
                           count: env.sharedItems.items.count, showDivider: true) {
                        leadingTile(Icons.share,
                                    fill: Color(rgb: env.theme.active.accent).opacity(0.14),
                                    iconColor: Color(rgb: env.theme.active.accent), iconSize: 16)
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
                    navRow(VaultRoute.category(category), title: Text(category.title),
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
                    navRow(VaultRoute.tag(entry.tag), title: Text(verbatim: entry.tag),
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
            navRow(VaultRoute.archive, title: Text("Archive"),
                   count: env.repository.archived.count, showDivider: true) {
                leadingTile(Icons.archive, fill: VaultColors.fill,
                            iconColor: env.theme.active.color(.iconSecondary), iconSize: 16)
            }
            navRow(VaultRoute.recentlyDeleted, title: Text("Recently Deleted"),
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
                    .frame(width: Metric.badgeTile)
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

    // MARK: - Row + container helpers

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
    /// + chevron, with a leading-inset hairline divider.
    @ViewBuilder
    private func navRow<Route: Hashable, Leading: View>(
        _ route: Route,
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
                        .padding(.leading, Space.s4 + Metric.badgeTile + Space.s3)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// `Metric.badgeTile` rounded leading badge so every row has a consistent tinted icon tile.
    private func leadingTile(_ icon: String, fill: Color, iconColor: Color, iconSize: CGFloat) -> some View {
        // Inset Space.s4 from the groupedCard's Radius.lg edge (row horizontal padding) — concentric, not eyeballed.
        RoundedRectangle(cornerRadius: Radius.concentric(outer: Radius.lg, inset: Space.s4), style: .continuous)
            .fill(fill)
            .frame(width: Metric.badgeTile, height: Metric.badgeTile)
            .overlay(PolarisIcon(icon, size: iconSize).foregroundStyle(iconColor))
    }
}
