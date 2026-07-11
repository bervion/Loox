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

    /// Local mirror of the field text — the digit-strip/cap happens in `onChange`
    /// (assign-back re-enters once, then stops), matching `CardNumberFieldEditor`'s
    /// pattern: normalize-via-Binding-setter drops mid-keystroke pushes on iOS 17+.
    @State private var text = ""

    var body: some View {
        ZStack(alignment: .leading) {
            TextField(placeholder, text: $text)
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
        .onAppear { text = value }
        .onChange(of: text) { _, new in
            guard new != value else { return }   // synced from storage — nothing to do
            let normalized = String(PaymentCard.digitsOnly(new).prefix(maxLength))
            if normalized != new { text = normalized }
            value = normalized
        }
        .onChange(of: value) { _, new in
            if text != new { text = new }
        }
    }
}
