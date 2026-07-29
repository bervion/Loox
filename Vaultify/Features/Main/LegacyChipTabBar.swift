import SwiftUI

/// Floating chip tab bar for pre-iOS-26 shells (17.6–18.x). On those systems the
/// native `TabView` bar renders transparent at the scroll edge — bare icons
/// sitting on the canvas with no surface — so `MainTabView` hides it and mounts
/// this instead: a solid floating pill with the four tab icons. iOS 26 keeps the
/// native Liquid Glass bar untouched.
///
/// Deliberately static (user re-approved a custom bar for legacy OSes 260711):
/// solid surface, no glass, no animated indicator — the removed custom shell's
/// switch latency came from its glass/indicator motion, none of which returns.
struct LegacyChipTabBar: View {
    @Binding var selection: VaultTab

    @Environment(AppEnvironment.self) private var env

    /// Ring of canvas around the ACTIVE chip: bar height 62 − indicator 46 = 8pt
    /// top/bottom, so the horizontal edge inset must also be 8pt. Items are fixed
    /// at indicator width (not flexible columns) — flexible columns center the
    /// end icons deep inside their cell and the edge gap balloons.
    var body: some View {
        let theme = env.theme.active
        HStack(spacing: 0) {
            ForEach(Array(VaultTab.allCases.enumerated()), id: \.element.id) { index, tab in
                if index > 0 { Spacer(minLength: Space.s2) }
                tabButton(tab, theme: theme)
            }
        }
        .padding(.horizontal, (TabBarMetric.height - TabBarMetric.indicatorSize) / 2)
        .frame(height: TabBarMetric.height)
        .background(Color(rgb: theme.surfaceFloatingSolid), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(rgb: theme.separator), lineWidth: 0.5))
        .elevation(.level2)
        .padding(.horizontal, TabBarMetric.horizontalInset)
        .padding(.bottom, TabBarMetric.bottomOffset)
    }

    @ViewBuilder
    private func tabButton(_ tab: VaultTab, theme: AppTheme) -> some View {
        let selected = selection == tab
        Button {
            selection = tab
        } label: {
            ZStack {
                if selected {
                    // Active chip: soft neutral circle + neutral filled icon
                    // (Apple-style black highlight, white in dark mode).
                    Circle()
                        .fill(Color(rgb: theme.primaryText).opacity(0.06))
                        .frame(width: TabBarMetric.indicatorSize,
                               height: TabBarMetric.indicatorSize)
                }
                VaultIcon(selected ? tab.iconSelected : tab.icon, size: Metric.iconTab)
                    .foregroundStyle(selected ? theme.color(.primary) : theme.color(.iconSecondary))
            }
            // Fixed indicator-width slot; full bar height keeps the hit area ≥44pt.
            .frame(width: TabBarMetric.indicatorSize)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.accessibilityLabel))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
    }
}
