import SwiftUI

/// Full-screen "Large Type" display: shows a value in large monospaced text with
/// digits / letters / symbols color-coded for easy reading aloud. Tap to dismiss.
struct LargeTypeView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            VaultColors.surface.ignoresSafeArea()

            ScrollView {
                Text(colorCoded)
                    .font(.system(size: 38, weight: .semibold, design: .monospaced))
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
                    .foregroundStyle(.secondary)
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
                piece.foregroundColor = .blue
            } else if character.isLetter {
                piece.foregroundColor = .primary
            } else {
                piece.foregroundColor = .red
            }
            result.append(piece)
        }
        return result
    }
}
