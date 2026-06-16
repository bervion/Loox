import SwiftUI

/// Onboarding step (after the master password / Emergency Kit, before biometrics):
/// pick the app appearance. The whole app reads `settings.appearance`, so the
/// choice previews live as the user taps.
struct ChooseThemeView: View {
    @Binding var selection: AppearanceMode
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            PolarisIcon(Icons.magic, size: 72).foregroundStyle(Color.accentColor)
            Text("Make it yours")
                .font(.largeTitle.bold())
                .padding(.top, Space.gutter)
            Text("Choose how Vaultify looks. You can change this anytime in Settings.")
                .font(.body)
                .themedForeground(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.s8)
                .padding(.top, Space.s2)

            VStack(spacing: Space.s3) {
                ForEach(AppearanceMode.allCases) { mode in
                    ThemeOptionRow(mode: mode, isSelected: selection == mode) {
                        withAnimation(.smooth(duration: 0.2)) { selection = mode }
                    }
                }
            }
            .padding(.top, 36)
            .padding(.horizontal, Space.s6)

            Spacer()
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .padding(.horizontal, Space.s6)
            .padding(.bottom, Space.s6)
        }
    }
}

private struct ThemeOptionRow: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Circle()
                    .fill(swatchStyle)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                Text(mode.title).font(.headline).themedForeground()
                Spacer()
                if isSelected {
                    PolarisIcon(Icons.checkCircle, size: 22).foregroundStyle(Color.accentColor)
                }
            }
            .padding(Space.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(VaultColors.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var swatchStyle: AnyShapeStyle {
        switch mode {
        case .system: AnyShapeStyle(LinearGradient(colors: [.white, .black], startPoint: .leading, endPoint: .trailing))
        case .light: AnyShapeStyle(Color.white)
        case .dark: AnyShapeStyle(Color.black)
        }
    }
}
