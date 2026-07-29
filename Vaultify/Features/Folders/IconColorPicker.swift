import SwiftUI

/// Icon + color chooser for a Space. Shows a live `FolderBadge` preview and the color swatches
/// inline, and hands the icon itself to `IconPickerSheet` — the catalog is far too large to sit
/// inside a `Form` section the way the old 66-glyph grid did.
struct IconColorPicker: View {
    @Binding var icon: String
    @Binding var color: FolderColor
    @Environment(AppEnvironment.self) private var env
    @State private var showIconPicker = false

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
                                    Circle()
                                        .strokeBorder(env.theme.active.color(.primary).opacity(0.6), lineWidth: 2)
                                        .padding(-3)
                                }
                            }
                            .frame(width: Metric.hitMin, height: Metric.hitMin)
                            .contentShape(.rect)
                            .onTapGesture { color = swatch }
                    }
                }
            }

            section(title: "Icon") {
                Button { showIconPicker = true } label: {
                    HStack(spacing: Space.s3) {
                        VaultIcon(icon, size: Metric.iconUtility)
                            .foregroundStyle(color.tint)
                        Text("Choose icon")
                            .vaultType(.body)
                            .themedForeground(.primary)
                        Spacer(minLength: Space.s2)
                        VaultIcon(Icons.chevronRight, size: Metric.iconCompact)
                            .themedForeground(.iconSecondary)
                    }
                    .frame(minHeight: Metric.hitMin)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showIconPicker) {
            IconPickerSheet(selected: icon) { icon = $0 }
        }
    }

    @ViewBuilder private func section(title: LocalizedStringKey,
                                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).vaultType(.sectionLabel).themedForeground(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
    }
}
