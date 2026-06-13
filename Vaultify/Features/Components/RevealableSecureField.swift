import SwiftUI

/// A secure text field with a reveal/hide toggle, in a rounded container.
struct RevealableSecureField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    var monospaced: Bool = true
    @State private var reveal = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if reveal {
                    TextField(title, text: $text)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(.password)
            .font(monospaced ? .vaultMono() : .body)
            .focused($focused)

            if !text.isEmpty {
                Button {
                    reveal.toggle()
                    Haptics.tap()
                } label: {
                    PolarisIcon(reveal ? Icons.hide : Icons.reveal, size: 20)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
