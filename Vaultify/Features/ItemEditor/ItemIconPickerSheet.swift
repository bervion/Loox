import SwiftUI

/// Grid of every Polaris icon for picking an item's thumbnail icon.
struct ItemIconPickerSheet: View {
    let selected: String?
    let onPick: (String) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.s2), count: 5)

    var body: some View {
        VaultSheetScaffold(title: "Choose icon",
                           leading: { EmptyView() },
                           trailing: { SheetDismissButton("Done") }) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Space.s2) {
                    ForEach(PolarisIconCatalog.all, id: \.self) { name in
                        Button {
                            onPick(name)
                            dismiss()
                        } label: {
                            PolarisIcon(name, size: Metric.iconUtility)
                                .themedForeground(name == selected ? .accent : .iconPrimary)
                                .frame(width: Metric.hitMin, height: Metric.hitMin)
                                .frame(maxWidth: .infinity)
                                .background(name == selected ? env.theme.active.color(.accentSoft) : VaultColors.fill,
                                            in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Space.gutter)
            }
            .scrollIndicators(.hidden)
        }
    }
}
