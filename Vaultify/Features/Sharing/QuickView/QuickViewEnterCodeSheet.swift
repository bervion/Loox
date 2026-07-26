import SwiftUI

/// Manual code entry — format `XXXX-XXXX`, validated client-side (charset +
/// checksum) before ever calling `resolve(code:)`.
struct QuickViewEnterCodeSheet: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Exactly what the field shows — kept in `XXXX-XXXX` shape on every
    /// keystroke. A computed Binding that reformatted inside `set` could not do
    /// this reliably: SwiftUI does not re-read `get` for a value the field
    /// believes it already holds, so the uppercasing and the dash only
    /// appeared once something else forced a redraw.
    @State private var text = ""
    @State private var showFormatError = false

    private var canonical: String { QuickViewHumanCode.normalize(text) }
    private var isValid: Bool { QuickViewHumanCode.isValid(text) }

    var body: some View {
        VaultSheetScaffold(title: "Enter Code") {
            VStack(spacing: Space.s5) {
                Text("Type the code shown in your browser.")
                    .vaultType(.callout).themedForeground(.secondary)
                    .multilineTextAlignment(.center)

                TextField("XXXX-XXXX", text: $text)
                    .font(.vaultCode(size: 22))
                    .multilineTextAlignment(.center)
                    .platformAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(Space.s4)
                    .background(VaultColors.surface)
                    .vaultCornerRadius(Radius.md)

                if showFormatError {
                    Text("That code doesn't look right. Double-check it and try again.")
                        .vaultType(.footnote).themedForeground(.destructive)
                        .multilineTextAlignment(.center)
                }

                Button {
                    guard isValid else { showFormatError = true; return }
                    dismiss()
                    onSubmit(canonical)
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                .disabled(canonical.count < QuickViewHumanCode.length)
            }
            .padding(Space.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: text) { _, newValue in
                // Anything longer than the code is a paste that carried extra
                // text ("Code: ABCD-EFGH", a whole URL). Silently keeping the
                // first eight symbols would show a well-formed code that is
                // simply the wrong one, so say so immediately rather than
                // letting the user discover it at Continue.
                let overflowed = QuickViewHumanCode.normalize(newValue).count
                    > QuickViewHumanCode.length
                let shaped = QuickViewHumanCode.liveFormatted(newValue)
                if shaped != newValue { text = shaped }
                showFormatError = overflowed
            }
        }
    }
}
