import SwiftUI

/// The Vault tab landing: a List with dashboard rows on top (Quick Access,
/// Spaces, Tags) followed by all items grouped by category — so opening the app
/// surfaces both context and the items themselves. Each dashboard row hides
/// itself when empty; item rows keep the standard swipe actions.
struct HomeDashboard: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var path: NavigationPath

    private func items(for category: ItemCategory) -> [VaultItem] {
        env.repository.items.filter { $0.category == category }.sorted { $0.updatedAt > $1.updatedAt }
    }
    private var visibleCategories: [ItemCategory] {
        ItemCategory.allCases.filter { !items(for: $0).isEmpty }
    }

    private var hasQuickAccess: Bool {
        env.repository.items.contains(where: \.favorite) || !env.repository.recentlyUsed(limit: 1).isEmpty
    }

    var body: some View {
        List {
            if hasQuickAccess { dashboardRow { QuickAccessSection(path: $path) } }
            if env.repository.folders.count >= 2 { dashboardRow { SpacesSection(path: $path) } }
            if !env.repository.allTags().isEmpty { dashboardRow { TagsSection(path: $path) } }

            ForEach(visibleCategories) { category in
                Section {
                    ForEach(items(for: category)) { VaultItemRowLink(item: $0) }
                } header: {
                    HStack {
                        Text(category.title)
                        Spacer()
                        Text("\(items(for: category).count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// A full-bleed, separator-free, transparent List row hosting a dashboard
    /// section (the section draws its own cards over the grouped background).
    private func dashboardRow(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
