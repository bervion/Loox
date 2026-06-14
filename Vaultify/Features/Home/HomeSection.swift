import SwiftUI

/// One Home dashboard section. Each renders a horizontal group of item cards.
enum HomeSection: String, CaseIterable, Identifiable {
    case pinned, favorite, recentlyCreated, frequentlyUsed, recentlyUsed, recentlyModified

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pinned: "Pinned"
        case .favorite: "Favorites"
        case .recentlyCreated: "Recently Created"
        case .frequentlyUsed: "Frequently Used"
        case .recentlyUsed: "Recently Used"
        case .recentlyModified: "Recently Modified"
        }
    }

    func items(_ repo: VaultRepository) -> [VaultItem] {
        switch self {
        case .pinned: repo.pinnedItems
        case .favorite: repo.items.filter(\.favorite)
        case .recentlyCreated: repo.recentlyCreated(limit: 12)
        case .frequentlyUsed: repo.frequentlyUsed(limit: 12)
        case .recentlyUsed: repo.recentlyUsed(limit: 12)
        case .recentlyModified: repo.recentlyModified(limit: 12)
        }
    }
}

/// A Home section: a title over a horizontal row of tappable item cards.
struct HomeSectionView: View {
    let title: LocalizedStringKey
    let items: [VaultItem]
    @Binding var path: NavigationPath

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        Button { path.append(item.id) } label: { ItemCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// Compact item card used across Home sections.
struct ItemCard: View {
    let item: VaultItem
    @Environment(\.appTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FaviconView(urlString: item.urlField?.value, category: item.category, size: 36)
            Text(item.title.isEmpty ? "Untitled" : item.title)
                .font(.subheadline.weight(.medium)).lineLimit(1).foregroundStyle(.primary)
            if let sub = item.subtitle, !sub.isEmpty {
                Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 132, alignment: .leading)
        .padding(12)
        .background(Color(rgb: theme.elevatedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
