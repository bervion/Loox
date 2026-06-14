import SwiftUI

/// The Vault tab landing: Quick Access → Spaces → Tags → All Items entry. A
/// scrollable dashboard so opening the app surfaces context and frequent items.
struct HomeDashboard: View {
    @Binding var path: NavigationPath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                QuickAccessSection()
                SpacesSection(path: $path)
                TagsSection()
                allItemsLink
            }
            .padding(.vertical, 16)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var allItemsLink: some View {
        NavigationLink(value: VaultRoute.all) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.tertiarySystemFill)).frame(width: 38, height: 38)
                    .overlay(PolarisIcon("ic_apps_filled", size: 20).foregroundStyle(.secondary))
                Text("All Items").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                PolarisIcon(Icons.chevronRight, size: 14).foregroundStyle(.tertiary)
            }
            .padding(14).frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}
