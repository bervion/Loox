import SwiftUI

/// Reusable icon + color chooser for a folder. Shows a live `FolderBadge`
/// preview, a row of color swatches, and a grid of curated Polaris icons.
struct IconColorPicker: View {
    @Binding var icon: String
    @Binding var color: FolderColor
    @Environment(AppEnvironment.self) private var env

    private let iconColumns = [GridItem(.adaptive(minimum: 54), spacing: 12)]
    private let colorColumns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        VStack(spacing: Space.s5) {
            FolderBadge(icon: icon, color: color, size: 64).padding(.top, Space.s1)

            section(title: "Color") {
                LazyVGrid(columns: colorColumns, spacing: 12) {
                    ForEach(FolderColor.palette) { swatch in
                        Circle()
                            .fill(swatch.tint)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if swatch == color {
                                    Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 2).padding(-3)
                                }
                            }
                            .contentShape(.rect)
                            .onTapGesture { color = swatch }
                    }
                }
            }

            section(title: "Icon") {
                LazyVGrid(columns: iconColumns, spacing: 12) {
                    ForEach(CuratedFolderIcons.all, id: \.self) { name in
                        let selected = name == icon
                        PolarisIcon(name, size: Metric.iconUtility)
                            .foregroundStyle(selected ? color.tint : env.theme.active.color(.primary))
                            .frame(width: 50, height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(selected ? color.tint.opacity(0.16) : VaultColors.surface)
                            )
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            Text(title).font(.subheadline.weight(.semibold)).themedForeground(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }
}
