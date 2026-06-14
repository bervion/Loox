import SwiftUI

/// Quick Access on Home: favorites and recently used, as compact horizontally
/// scrolling cards so the most-needed logins are one tap away. Hidden entirely
/// when there are neither favorites nor recents.
struct QuickAccessSection: View {
    @Environment(AppEnvironment.self) private var env

    private var favorites: [VaultItem] { env.repository.items.filter(\.favorite) }
    private var recents: [VaultItem] { env.repository.recentlyUsed(limit: 8) }

    var body: some View {
        if !favorites.isEmpty || !recents.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                if !favorites.isEmpty { group(title: "Favorites", items: favorites) }
                if !recents.isEmpty { group(title: "Recently Used", items: recents) }
            }
        }
    }

    @ViewBuilder private func group(title: LocalizedStringKey, items: [VaultItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(value: item.id) { QuickAccessCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct QuickAccessCard: View {
    let item: VaultItem
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
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
