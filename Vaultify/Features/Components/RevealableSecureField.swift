import SwiftUI

/// A secure text field with a reveal/hide toggle, in a rounded container.
struct RevealableSecureField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var monospaced: Bool = true
    @State private var reveal = false
    @FocusState private var focused: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Space.s2) {
            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(title)
                        .font(monospaced ? .vaultMono() : .body)
                        .foregroundStyle(Color(rgb: theme.secondaryText))
                }
                Group {
                    if reveal {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .font(monospaced ? .vaultMono() : .body)
                .focused($focused)
                .foregroundStyle(Color(rgb: theme.primaryText))
            }

            if !text.isEmpty {
                Button {
                    reveal.toggle()
                    Haptics.tap()
                } label: {
                    PolarisIcon(reveal ? Icons.hide : Icons.reveal, size: Metric.iconInline)
                        .foregroundStyle(Color(rgb: theme.secondaryText))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Space.s3)
        .background(Color(rgb: theme.controlBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
