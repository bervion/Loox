import SwiftUI

/// A single item row used in the vault list, search results, and trash. Shows
/// the website favicon (falling back to the category badge) and — when the item
/// belongs to a Space — a small colored Space chip, so you can tell e.g. the
/// "Work" GitHub from the "Personal" one at a glance. `showSpace` is off inside a
/// single-Space view where the chip would be redundant.
struct VaultItemRow: View {
    let item: VaultItem
    var showSpace = true
    @Environment(AppEnvironment.self) private var env

    private var folder: Folder? {
        guard showSpace, let id = item.folderId else { return nil }
        return env.repository.folders.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 12) {
            FaviconView(urlString: item.urlField?.value, category: item.category, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled" : item.title)
                    .font(.body)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if let folder { spaceChip(folder) }
            if item.pinned {
                PolarisIcon(Icons.pinFill, size: 12).foregroundStyle(Color.accentColor)
            }
            if item.favorite {
                PolarisIcon(Icons.starFill, size: 14)
                    .foregroundStyle(VaultColors.strengthMedium)
            }
        }
        .contentShape(.rect)
    }

    private func spaceChip(_ folder: Folder) -> some View {
        HStack(spacing: 4) {
            Circle().fill(folder.color.tint).frame(width: 7, height: 7)
            Text(folder.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(VaultColors.fill, in: Capsule())
    }
}
