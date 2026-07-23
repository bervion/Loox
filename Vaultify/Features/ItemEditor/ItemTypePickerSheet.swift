import SwiftUI

/// Reusable "what do you want to add" bottom sheet: a plain white canvas with the
/// dots ring fronting the vault mark (playing once), then one row per vault type
/// — a duotone glyph, a title, and a short description — replacing the old
/// item-type popup menu. Presented from Home and Security.
///
/// The close control lives in the nav-bar toolbar (same as the item editor), so
/// iOS 26 renders it as the standard circular liquid-glass X; the toolbar
/// background is hidden so the white canvas reads full-bleed behind it.
struct ItemTypePickerSheet: View {
    /// Called with the chosen category; the sheet dismisses itself first, so the
    /// caller can present the editor from the sheet's `onDismiss`.
    let onSelect: (ItemCategory) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Plain white canvas (near-black in dark) — Apple-Account-sheet idiom.
                Color(rgb: env.theme.active.background).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Space.s5) {
                        LooxDotsAvatar(size: 104, revealsOnAppear: true, centerIcon: "dt_vault")
                            .padding(.top, Space.s4)

                        VStack(alignment: .leading, spacing: Space.s2) {
                            Text("New item")
                                .vaultType(.screenTitle)
                                .themedForeground(.primary)
                            Text("Choose the kind of item to add to your vault.")
                                .vaultType(.subhead)
                                .themedForeground(.secondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Space.gutter)

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
            }
            .navigationTitle("")
            .platformNavigationBarTitleDisplayMode(.inline)
            .platformHiddenNavigationBarBackground()
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    // Icon-only toolbar button → iOS 26 gives it the circular
                    // liquid-glass close treatment automatically (matches the editor).
                    Button { dismiss() } label: {
                        PolarisIcon(Icons.close, size: Metric.iconInline)
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .platformPresentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func typeRow(_ category: ItemCategory) -> some View {
        Button {
            onSelect(category)
            dismiss()
        } label: {
            // Outer row centers the chevron vertically; the inner group top-aligns
            // the glyph to the title line.
            HStack(alignment: .center, spacing: Space.s2) {
                HStack(alignment: .top, spacing: Space.s3) {
                    // Brand blue duotone glyph, aligned to the title's top line.
                    PolarisIcon(category.avatarIcon, size: 28)
                        .foregroundStyle(Color.looxBlue)
                        .frame(width: Metric.controlSmall, alignment: .top)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .vaultType(.headline)
                            .themedForeground(.primary)
                        Text(category.creationBlurb)
                            .vaultType(.subhead)
                            .themedForeground(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
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
}
