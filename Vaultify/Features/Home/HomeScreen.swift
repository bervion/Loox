import SwiftUI

/// Home tab: a personalized dashboard of Pinned / Favorites / Recently Created /
/// Frequently Used (+ optional Recently Used / Modified) item-card groups, plus a
/// Utilities section. Settings (gear) and Customize live in the header/footer.
struct HomeScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var path = NavigationPath()
    @State private var editorTarget: EditorTarget?
    @State private var showSettings = false
    @State private var showGenerator = false
    @State private var showCustomize = false

    /// Default-ON sections + the optional ones the user enabled in Customize.
    private var sections: [HomeSection] {
        var list: [HomeSection] = [.pinned, .favorite, .recentlyCreated, .frequentlyUsed]
        if env.settings.homeShowRecentlyUsed { list.append(.recentlyUsed) }
        if env.settings.homeShowRecentlyModified { list.append(.recentlyModified) }
        return list
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if env.repository.items.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .themedWallpaper(env.theme.wallpaper, fallback: Color(rgb: env.theme.active.background))
            .navigationTitle("Vault")
            .toolbar { toolbar }
            .vaultNavigationDestinations()
            .sheet(item: $editorTarget) { ItemEditorScreen(target: $0) }
            .sheet(isPresented: $showSettings) { SettingsScreen() }
            .sheet(isPresented: $showGenerator) { GeneratorScreen() }
            .sheet(isPresented: $showCustomize) { CustomizeHomeScreen() }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(sections) { section in
                    let items = section.items(env.repository)
                    if !items.isEmpty {
                        HomeSectionView(title: section.title, items: items, path: $path)
                    }
                }
                UtilitiesSection(showGenerator: $showGenerator)
                customizeButton
            }
            .padding(.vertical, 16)
        }
    }

    private var customizeButton: some View {
        Button { showCustomize = true } label: {
            Label { Text("Customize Home") } icon: { PolarisIcon(Icons.edit, size: 15) }
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.top, 4)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label { Text("Your vault is empty") } icon: { PolarisIcon(Icons.lockFill, size: 48) }
        } description: {
            Text("Add your first login, card, or secure note.")
        } actions: {
            Menu { addMenu } label: { Text("Add Item") }.buttonStyle(.themedProminent)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { PolarisIcon(Icons.settings, size: 24) }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu { addMenu } label: { PolarisIcon(Icons.add, size: 26) }
        }
    }

    @ViewBuilder private var addMenu: some View {
        ForEach(ItemCategory.allCases) { category in
            Button { editorTarget = .new(category) } label: {
                Label { Text(category.title) } icon: { PolarisIcon(category.iconAsset) }
            }
        }
    }
}
