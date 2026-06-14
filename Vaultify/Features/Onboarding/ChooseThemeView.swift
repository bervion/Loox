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
                .padding(.top, 16)
            Text("Choose how Vaultify looks. You can change this anytime in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)

            VStack(spacing: 12) {
                ForEach(AppearanceMode.allCases) { mode in
                    ThemeOptionRow(mode: mode, isSelected: selection == mode) {
                        withAnimation(.smooth(duration: 0.2)) { selection = mode }
                    }
                }
            }
            .padding(.top, 36)
            .padding(.horizontal, 24)

            Spacer()
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.themedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
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
                Text(mode.title).font(.headline).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    PolarisIcon(Icons.checkCircle, size: 22).foregroundStyle(Color.accentColor)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
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
