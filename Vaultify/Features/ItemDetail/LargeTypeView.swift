import SwiftUI

/// Full-screen "Large Type" display: shows a value in large monospaced text with
/// digits / letters / symbols color-coded for easy reading aloud. Tap to dismiss.
struct LargeTypeView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @ScaledMetric(relativeTo: .largeTitle) private var fontSize: CGFloat = 38

    var body: some View {
        ZStack {
            VaultColors.surface.ignoresSafeArea()

            ScrollView {
                Text(colorCoded)
                    .font(.system(size: fontSize, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineSpacing(8)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 60)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                PolarisIcon(Icons.close, size: 22)
                    .themedForeground(.secondary)
                    .padding(10)
                    .background(Circle().fill(VaultColors.fill))
            }
            .padding(16)
        }
        .contentShape(.rect)
        .onTapGesture { dismiss() }
    }

    /// Digits in blue, symbols in red, letters in the primary color — the
    /// standard "readable password" coloring.
    private var colorCoded: AttributedString {
        var result = AttributedString()
        for character in text {
            var piece = AttributedString(String(character))
            if character.isNumber {
                piece.foregroundColor = VaultColors.category(.login)
            } else if character.isLetter {
                piece.foregroundColor = env.theme.active.color(.primary)
            } else {
                piece.foregroundColor = env.theme.active.color(.destructive)
            }
            result.append(piece)
        }
        return result
    }
}
