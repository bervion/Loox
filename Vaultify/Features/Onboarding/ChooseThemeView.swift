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
                    // Brand lockup ships light + dark wordmark variants, so it flips
                    // live as the user previews System/Light/Dark.
                    BrandLockup(height: 38)
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

    /// All appearance options grouped in one card with hairline separators.
    private var themeCard: some View {
        VStack(spacing: 0) {
            ForEach(AppearanceMode.allCases) { mode in
                ThemeOptionRow(mode: mode, isSelected: selection == mode) {
                    Haptics.tap()
                    withAnimation(.vault(.smooth(duration: 0.2), reduceMotion: reduceMotion)) { selection = mode }
                }
                if mode != AppearanceMode.allCases.last {
                    Divider().padding(.leading, 54)   // align past the swatch + gap
                }
            }
        }
        .background(Color(rgb: theme.elevatedBackground),
                    in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .elevation(.level2)
    }
}

private struct ThemeOptionRow: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Space.s3) {
                Circle()
                    .fill(swatchStyle)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                Text(mode.title).vaultType(.headline).themedForeground()
                Spacer(minLength: Space.s2)
                if isSelected {
                    PolarisIcon(Icons.checkCircle, size: 22).foregroundStyle(VaultColors.accent)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Literal light/dark preview swatches — raw white/black is intentional here.
    private var swatchStyle: AnyShapeStyle {
        switch mode {
        case .system: AnyShapeStyle(LinearGradient(colors: [.white, .black], startPoint: .leading, endPoint: .trailing))
        case .light: AnyShapeStyle(Color.white)
        case .dark: AnyShapeStyle(Color.black)
        }
    }
}
