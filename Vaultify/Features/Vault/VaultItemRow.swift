import SwiftUI

/// A single item row used in the vault list, search results, and trash. Shows
/// the website favicon (falling back to the category badge) and — when the item
/// belongs to a Space — a small colored Space chip, so you can tell e.g. the
/// "Work" GitHub from the "Personal" one at a glance. `showSpace` is off inside a
/// single-Space view where the chip would be redundant.
struct VaultItemRow: View {
    let item: VaultItem
    var showSpace = true
    /// Search query whose tokens are emphasized inside the title (search results
    /// only) — shows *why* a row matched. nil elsewhere.
    var highlight: String? = nil
    @Environment(AppEnvironment.self) private var env

    private var folder: Folder? {
        guard showSpace, let id = item.folderId else { return nil }
        return env.repository.folders.first { $0.id == id }
    }

    /// This item is owned here AND has an outgoing share that hasn't reached
    /// Active yet (design 12a "SHARING…" item badge). Recipient-side
    /// projections never own `SharingStore` records, so this is naturally
    /// empty for them.
    private var hasPendingShare: Bool {
        env.sharingStore.shares(forItem: item.id).contains { $0.status != .active }
    }

    var body: some View {
        HStack(spacing: Space.s3) {
            FaviconView(urlString: item.urlField?.value, category: item.category, size: 40, title: item.title)
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
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                    }
                }
                .font(.body)
                .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .themedForeground(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            // Prioritize the Space chip over the title: a long title truncates so the chip
            // ("which vault") stays fully visible instead of being squeezed to nothing.
            if let folder {
                spaceChip(folder).layoutPriority(1)
            }
            // Recipient-side projection — read-only, lives in no Space, so the
            // chip slot is free for the "Shared" marker.
            if item.sharedOrigin != nil {
                sharedChip.layoutPriority(1)
            } else if hasPendingShare {
                sharingBadge.layoutPriority(1)
            }
        }
        // Pinned → a pin glyph overlaid at the row's outermost top-right corner.
        .overlay(alignment: .topTrailing) {
            if item.pinned {
                PolarisIcon(Icons.pinFill, size: 11)
                    .foregroundStyle(Color.accentColor)
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
        PolarisIcon(Icons.starFill, size: 10)
            .foregroundStyle(VaultColors.favoriteStar)
            .frame(width: 16, height: 16)
            .background(Color(rgb: env.theme.active.elevatedBackground),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color(rgb: env.theme.active.separator), lineWidth: 0.5)
            )
            .offset(x: 3, y: 3)
    }

    private var sharedChip: some View {
        HStack(spacing: 4) {
            PolarisIcon(Icons.share, size: 9).themedForeground(.accent)
            Text("Shared").font(.caption2).themedForeground(.secondary)
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
        .background(VaultColors.fill, in: Capsule())
    }

    /// Design 12a: "SHARING…" — an outgoing share on this item is still
    /// pending (invite sent / accepted / ready to confirm), visible right in
    /// the list without opening the item.
    private var sharingBadge: some View {
        HStack(spacing: 3) {
            PolarisIcon(Icons.clock, size: 9).themedForeground(.warning)
            Text("SHARING…").font(.caption2).fontWeight(.semibold).themedForeground(.warning)
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
        .background(Color(rgb: env.theme.active.warningSoft), in: Capsule())
    }

    private func spaceChip(_ folder: Folder) -> some View {
        HStack(spacing: 4) {
            Circle().fill(folder.color.tint).frame(width: 7, height: 7)
            Text(folder.name).font(.caption2).themedForeground(.secondary)
                .lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s1)
        .background(VaultColors.fill, in: Capsule())
    }
}
