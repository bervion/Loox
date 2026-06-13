import SwiftUI

/// A single item row used in the vault list, search results, and trash.
/// Shows the website favicon for logins (falling back to the category badge).
struct VaultItemRow: View {
    let item: VaultItem

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
            Spacer(minLength: 8)
            if item.favorite {
                PolarisIcon(Icons.starFill, size: 14)
                    .foregroundStyle(VaultColors.strengthMedium)
            }
        }
        .contentShape(.rect)
    }
}
