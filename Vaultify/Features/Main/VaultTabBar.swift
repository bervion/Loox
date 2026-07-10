import SwiftUI

/// The floating, icon-only shell tab bar (Design System: Threads-style minimal bar).
/// Four tabs, no text. A soft accent pill slides behind the active icon with a
/// low-bounce spring; a light haptic fires on change. Background is the system
/// material with a solid Reduce-Transparency fallback. Sits as a bottom overlay.
struct VaultTabBar: View {
    @Binding var selection: VaultTab
    var badges: Set<VaultTab> = []

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        let theme = env.theme.active
        HStack(spacing: 0) {
            ForEach(VaultTab.allCases) { tab in
                let selected = selection == tab
                Button { select(tab) } label: {
                    ZStack {
                        if selected {
                            Color.clear
                                .frame(width: TabBarMetric.indicatorSize, height: TabBarMetric.indicatorSize)
                                .vaultTabSelectionSurface()
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                        PolarisIcon(selected ? tab.iconSelected : tab.icon, size: Metric.iconTab)
                            .foregroundStyle(Color(rgb: selected ? theme.accent : theme.iconSecondary))
                            .overlay(alignment: .topTrailing) { badgeDot(tab) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Metric.hitMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(TabPressStyle(reduceMotion: reduceMotion))
                .accessibilityLabel(Text(tab.accessibilityLabel))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(height: TabBarMetric.height)
        .vaultTabBarSurface()
        .padding(.horizontal, TabBarMetric.horizontalInset)
        .accessibilityElement(children: .contain)
    }

    private func select(_ tab: VaultTab) {
        guard selection != tab else { return }
        // Minor selection change → `.tap()`, matching the app-wide haptic vocabulary
        // (every other selection/toggle site uses `.tap()`, not `.selection()`).
        Haptics.tap()
        if reduceMotion {
            selection = tab
        } else {
            withAnimation(Motion.spring) { selection = tab }
        }
    }

    @ViewBuilder private func badgeDot(_ tab: VaultTab) -> some View {
        if badges.contains(tab) {
            Circle()
                .fill(Color(rgb: env.theme.active.destructive))
                .frame(width: TabBarMetric.badgeDot, height: TabBarMetric.badgeDot)
                .overlay(Circle().strokeBorder(Color(rgb: env.theme.active.surfaceFloatingSolid), lineWidth: 1.5))
                .offset(x: 3, y: -2)
        }
    }
}

/// Subtle press feedback for a tab button — DS press scale, reduce-motion aware.
private struct TabPressStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
            .animation(.vault(Motion.standard, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
