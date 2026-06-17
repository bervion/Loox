import SwiftUI

/// Legacy item card kept for any callers that still render a compact horizontal
/// card (e.g. the old HomeSectionView). New Home assembly uses VaultItemRow
/// inside grouped cards instead.
///
/// Note: the old `HomeSection` enum and `HomeSectionView` are intentionally
/// removed — the DS-spec Home no longer uses personalised card-scroll sections.
/// `ItemCard` is retained in case other feature screens reference it.
struct ItemCard: View {
    let item: VaultItem
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            FaviconView(urlString: item.urlField?.value, category: item.category, size: 36)
            Text(item.title.isEmpty ? "Untitled" : item.title)
                .font(.subheadline.weight(.medium)).lineLimit(1).themedForeground()
            if let sub = item.subtitle, !sub.isEmpty {
                Text(sub).font(.caption).themedForeground(.secondary).lineLimit(1)
            }
        }
        .frame(width: 132, alignment: .leading)
        .padding(Space.s3)
        .background(Color(rgb: theme.elevatedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}
