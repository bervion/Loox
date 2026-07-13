import SwiftUI

/// Onboarding step (after the master password / Emergency Kit, before biometrics):
/// pick the app appearance. The whole app reads `settings.appearance`, so the
/// choice — and the brand mark — preview live as the user taps.
/// Layout mirrors the other onboarding steps: top-aligned, left-aligned, Loox mark.
struct ChooseThemeView: View {
    @Binding var selection: AppearanceMode
    let onContinue: () -> Void
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    // Loox dots mark (the Home empty-avatar look), centred,
                    // revealing its rings on appear.
                    LooxDotsAvatar(size: 100, revealsOnAppear: true)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Space.s6)
                    Text("Make it yours")
                        .vaultType(.screenTitle)
                    Text("Choose how Loox looks. You can change this anytime in Settings.")
                        .vaultType(.subhead).themedForeground(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Space.s2)

                themeCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s6)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.gutter)
        }
    }

    /// Appearance options as preview cards (same mini vault-style preview the
    /// Settings Appearance screen uses) — the user sees what each mode looks
    /// like before picking. System shows a split light/dark preview.
    private var themeCard: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Space.s3)], spacing: Space.s3) {
            ForEach(AppearanceMode.allCases) { mode in
                ThemePreviewCard(mode: mode, isSelected: selection == mode) {
                    Haptics.tap()
                    withAnimation(.vault(.smooth(duration: 0.2), reduceMotion: reduceMotion)) { selection = mode }
                }
            }
        }
    }
}

/// One tappable appearance card with the mini vault-style preview (cards over a
/// background). System renders a diagonal-split day/night preview.
private struct ThemePreviewCard: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    preview
                    if isSelected {
                        PolarisIcon(Icons.checkCircle, size: 18)
                            .foregroundStyle(Color(rgb: primaryPalette.accent))
                            .padding(5)
                            .background(Color(rgb: primaryPalette.background), in: Circle())
                            .padding(5)
                    }
                }
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? env.theme.uiTint : Color(rgb: primaryPalette.separator),
                                  lineWidth: isSelected ? 2.5 : 1))
                Text(mode.title).vaultType(.caption).themedForeground().lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var primaryPalette: AppTheme {
        mode == .dark ? BuiltinThemes.palette(.night) : BuiltinThemes.palette(.day)
    }

    @ViewBuilder private var preview: some View {
        switch mode {
        case .light: miniVault(BuiltinThemes.palette(.day))
        case .dark: miniVault(BuiltinThemes.palette(.night))
        case .system:
            // Split preview: day on the left half, night on the right half
            // (the mask's clear half hides, its opaque half shows).
            ZStack {
                miniVault(BuiltinThemes.palette(.day))
                miniVault(BuiltinThemes.palette(.night))
                    .mask(HStack(spacing: 0) { Color.clear; Color.black })
            }
        }
    }

    /// The same mini preview the Settings theme picker draws.
    private func miniVault(_ palette: AppTheme) -> some View {
        ZStack {
            Rectangle().fill(Color(rgb: palette.background))
            VStack(spacing: 5) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 5) {
                        Circle().fill(Color(rgb: palette.accent)).frame(width: 9, height: 9)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(rgb: palette.secondaryText)).frame(height: 5)
                    }
                    .padding(Space.s1)
                    .background(Color(rgb: palette.elevatedBackground),
                                in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                }
            }
            .padding(Space.s2)
        }
    }
}
