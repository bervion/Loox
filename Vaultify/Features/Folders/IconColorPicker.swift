import SwiftUI

/// Reusable icon + color chooser for a folder. Shows a live `FolderBadge`
/// preview, a row of color swatches, and a grid of curated Polaris icons.
struct IconColorPicker: View {
    @Binding var icon: String
    @Binding var color: FolderColor
    @Environment(AppEnvironment.self) private var env

    private let iconColumns = [GridItem(.adaptive(minimum: 54), spacing: Space.s3)]
    private let colorColumns = [GridItem(.adaptive(minimum: 44), spacing: Space.s3)]

    var body: some View {
        VStack(spacing: Space.s5) {
            FolderBadge(icon: icon, color: color, size: 64).padding(.top, Space.s1)

            section(title: "Color") {
                LazyVGrid(columns: colorColumns, spacing: Space.s3) {
                    ForEach(FolderColor.palette) { swatch in
                        // Visible swatch stays 34pt (Metric.controlSmall); tappable area widens
                        // to Metric.hitMin (44) via an invisible frame so the grid's already-
                        // reserved 44pt column is fully tappable, not just its center third.
                        Circle()
                            .fill(swatch.tint)
                            .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                            .overlay {
                                if swatch == color {
                                    Circle().strokeBorder(env.theme.active.color(.primary).opacity(0.6), lineWidth: 2).padding(-3)
                                }
                            }
                            .frame(width: Metric.hitMin, height: Metric.hitMin)
                            .contentShape(.rect)
                            .onTapGesture { color = swatch }
                    }
                }
            }

            section(title: "Icon") {
                LazyVGrid(columns: iconColumns, spacing: Space.s3) {
                    ForEach(CuratedFolderIcons.all, id: \.self) { name in
                        let selected = name == icon
                        PolarisIcon(name, size: Metric.iconUtility)
                            .foregroundStyle(selected ? color.tint : env.theme.active.color(.primary))
                            .frame(width: Metric.iconPickerTile, height: Metric.iconPickerTile)
                            .background(
                                // Metric.iconPickerTile * 0.28 = Radius.md — same proportional tile convention as
                                // FolderBadge/FaviconView at this size class.
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .fill(selected ? color.tint.opacity(0.16) : VaultColors.surface)
                            )
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .strokeBorder(color.tint, lineWidth: 2)
                                }
                            }
                            .contentShape(.rect)
                            .onTapGesture { icon = name }
                    }
                }
            }
        }
    }

    @ViewBuilder private func section(title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).vaultType(.sectionLabel).themedForeground(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }
}
