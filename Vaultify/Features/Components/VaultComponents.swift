import SwiftUI

/// Rounded, tinted badge showing a category's Polaris icon.
struct CategoryBadge: View {
    let category: ItemCategory
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(VaultColors.category(category).opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                PolarisIcon(category.iconAsset, size: size * 0.58)
                    .foregroundStyle(VaultColors.category(category))
            )
    }
}

/// Renders a stored field label so known English template labels localize via
/// the string catalog, while user-authored labels pass through verbatim.
func fieldLabelText(_ label: String) -> Text {
    Text(LocalizedStringKey(label))
}

/// A small pill used for category filters and tags.
struct FilterChip: View {
    let title: LocalizedStringResource
    let isSelected: Bool
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { PolarisIcon(icon, size: 15) }
                Text(title).font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : VaultColors.surface,
                        in: Capsule())
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
