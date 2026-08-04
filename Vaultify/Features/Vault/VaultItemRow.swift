import SwiftUI

/// A single item row used in the vault list, search results, and trash. Shows
/// the website favicon (falling back to the category badge); the item's Space
/// is deliberately NOT shown here — the detail screen states it, and the chip
/// made every list read heavier for a fact rarely needed at a glance.
struct VaultItemRow: View {
    let item: VaultItem
    /// Search query whose tokens are emphasized inside the title (search results
    /// only) — shows *why* a row matched. nil elsewhere.
    var highlight: String? = nil
    @Environment(AppEnvironment.self) private var env

    /// This item is owned here AND has an outgoing share that hasn't reached
    /// Active yet (design 12a "SHARING…" item badge). Recipient-side
    /// projections never own `SharingStore` records, so this is naturally
    /// empty for them.
    private var hasPendingShare: Bool {
        env.sharingStore.shares(forItem: item.id).contains { $0.status != .active }
    }

    var body: some View {
        HStack(spacing: Space.s3) {
            FaviconView(urlString: item.urlField?.value, category: item.category, size: 40,
                        title: item.title, iconAsset: item.iconAsset)
                // Favorite → a small star badge on the icon's bottom-right corner, so it
                // never competes with the Space chip for the row's trailing width.
                .overlay(alignment: .bottomTrailing) {
                    if item.favorite { favoriteBadge }
                }
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let highlighted = highlightedTitle {
                        Text(highlighted)
                    } else {
                        Text(verbatim: item.title.isEmpty ? appString("Untitled") : item.title)
                    }
                }
                .vaultType(.body)
                .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .vaultType(.caption)
                        .themedForeground(.secondary)
                        .lineLimit(1)
                }
                // Status metadata reads as its OWN line under the identity lines.
                // The previous trailing placement with layoutPriority squeezed the
                // TITLE down to a few characters whenever the badge ran long —
                // the row's payload lost to its metadata.
                if item.sharedOrigin != nil || hasPendingShare {
                    HStack(spacing: Space.s2) {
                        if item.sharedOrigin != nil {
                            sharedChip
                        } else if hasPendingShare {
                            sharingBadge
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        // Pinned → a pin glyph overlaid at the row's outermost top-right corner.
        .overlay(alignment: .topTrailing) {
            if item.pinned {
                VaultIcon(Icons.pinFill, size: 11)
                    .foregroundStyle(Color(rgb: env.theme.active.accent))
            }
        }
        .contentShape(.rect)
    }

    /// Title with each query token tinted accent + semibold (case/diacritic
    /// insensitive, so Vietnamese input matches unaccented storage and vice
    /// versa). nil when there is no query or the title is empty.
    private var highlightedTitle: AttributedString? {
        guard let highlight, !highlight.isEmpty, !item.title.isEmpty else { return nil }
        let title = item.title
        var attributed = AttributedString(title)
        let accent = env.theme.active.color(.accent)
        for token in highlight.split(separator: " ") {
            var searchStart = title.startIndex
            while searchStart < title.endIndex,
                  let r = title.range(of: token,
                                      options: [.caseInsensitive, .diacriticInsensitive],
                                      range: searchStart..<title.endIndex) {
                if let ar = Range(r, in: attributed) {
                    attributed[ar].foregroundColor = accent
                    attributed[ar].font = .body.weight(.semibold)
                }
                searchStart = r.upperBound
            }
        }
        return attributed
    }

    /// Star badge for the favorite state — yellow star on a small rounded-square tile filled
    /// with the row's own background (white in light, dark in dark) so it sits like a sticker
    /// on the favicon's bottom-right corner. A hairline keeps it crisp over any favicon.
    private var favoriteBadge: some View {
        VaultIcon(Icons.starFill, size: 10)
            .foregroundStyle(VaultColors.favoriteStar)
            .frame(width: 16, height: 16)
            .background(Color(rgb: env.theme.active.elevatedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                    .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5)
            )
            .offset(x: 3, y: 3)
    }

    private var sharedChip: some View {
        HStack(spacing: 4) {
            VaultIcon(Icons.share, size: 9).themedForeground(.accent)
            Text("Shared").vaultType(.caption).themedForeground(.secondary)
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
        .background(VaultColors.fill, in: Capsule())
    }

    /// Design 12a: "SHARING…" — an outgoing share on this item is still
    /// pending (invite sent / accepted / ready to confirm), visible right in
    /// the list without opening the item.
    private var sharingBadge: some View {
        HStack(spacing: 3) {
            VaultIcon(Icons.clock, size: 9).themedForeground(.warning)
            Text("SHARING…").vaultType(.caption).fontWeight(.semibold).themedForeground(.warning)
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
        .background(Color(rgb: env.theme.active.warningSoft), in: Capsule())
    }
}
