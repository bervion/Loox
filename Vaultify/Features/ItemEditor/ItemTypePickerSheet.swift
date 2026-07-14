import SwiftUI

/// Reusable "what do you want to add" bottom sheet: a plain white canvas with the
/// dots ring fronting the vault mark (playing once), then one row per vault type
/// — a duotone glyph, a title, and a short description — replacing the old
/// item-type popup menu. Presented from Home and Security.
struct ItemTypePickerSheet: View {
    /// Called with the chosen category; the sheet dismisses itself first, so the
    /// caller can present the editor from the sheet's `onDismiss`.
    let onSelect: (ItemCategory) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Plain white canvas (near-black in dark) — Apple-Account-sheet idiom.
            Color(rgb: env.theme.active.background).ignoresSafeArea()

            ScrollView {
                VStack(spacing: Space.s5) {
                    LooxDotsAvatar(size: 104, revealsOnAppear: true, centerIcon: "dt_vault")
                        .padding(.top, Space.s7)

                    VStack(spacing: Space.s2) {
                        Text("New item")
                            .vaultType(.screenTitle)
                            .themedForeground(.primary)
                        Text("Choose the kind of item to add to your vault.")
                            .vaultType(.subhead)
                            .themedForeground(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Space.s6)

                    VStack(spacing: Space.s3) {
                        ForEach(ItemCategory.allCases) { category in
                            typeRow(category)
                        }
                    }
                    .padding(.horizontal, Space.gutter)
                }
                .padding(.bottom, Space.s8)
            }
            .scrollIndicators(.hidden)

            closeButton
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func typeRow(_ category: ItemCategory) -> some View {
        Button {
            onSelect(category)
            dismiss()
        } label: {
            HStack(spacing: Space.s3) {
                PolarisIcon(category.avatarIcon, size: 30)
                    .foregroundStyle(VaultColors.category(category))
                    .frame(width: Metric.controlMedium, height: Metric.controlMedium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .vaultType(.headline)
                        .themedForeground(.primary)
                    Text(category.creationBlurb)
                        .vaultType(.subhead)
                        .themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s2)
                PolarisIcon(Icons.chevronRight, size: 14)
                    .themedForeground(.tertiary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: env.theme.active.secondaryBackground),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            PolarisIcon(Icons.close, size: Metric.iconInline)
                .themedForeground(.primary)
                .frame(width: Metric.hitMin, height: Metric.hitMin)
                .background(Color(rgb: env.theme.active.secondaryBackground), in: Circle())
        }
        .buttonStyle(.plain)
        .padding(Space.gutter)
    }
}
