import SwiftUI

/// Masked-reveal numeric code editor shared by the card's Security Code (CVV) and PIN
/// fields — the same Controlled-Reveal treatment as `EditorFieldRow`'s generic protected
/// case (masked bullets when unfocused, plaintext while typing), plus a numeric keypad and
/// a hard digit cap enforced as-you-type (CVV: brand-dependent 3/4 digits; PIN: 6 digits).
struct CardCodeFieldEditor: View {
    @Binding var value: String
    let maxLength: Int
    let placeholder: LocalizedStringKey
    @FocusState private var focused: Bool

    private var showsPlaintext: Bool { focused || value.isEmpty }

    var body: some View {
        ZStack(alignment: .leading) {
            TextField(placeholder, text: digitsBinding)
                .focused($focused)
                .font(value.isEmpty ? VaultType.body.font : .vaultCode())
                .platformKeyboardType(.numberPad)
                .platformAutocapitalization(.never)
                .autocorrectionDisabled()
                .opacity(showsPlaintext ? 1 : 0)
            if !showsPlaintext {
                Text(String(repeating: "•", count: 16))
                    .font(.vaultCode())
                    .themedForeground(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { focused = true }
                    .accessibilityHidden(true)
            }
        }
    }

    private var digitsBinding: Binding<String> {
        Binding(
            get: { value },
            set: { newValue in
                value = String(PaymentCard.digitsOnly(newValue).prefix(maxLength))
            }
        )
    }
}
