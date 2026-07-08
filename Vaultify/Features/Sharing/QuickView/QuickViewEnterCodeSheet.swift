import SwiftUI

/// Manual code entry — format `XXXX-XXXX`, validated client-side (charset +
/// checksum) before ever calling `resolve(code:)`.
struct QuickViewEnterCodeSheet: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var raw = ""
    @State private var showFormatError = false

    private var isValid: Bool { QuickViewHumanCode.isValid(raw) }

    var body: some View {
        VaultSheetScaffold(title: "Enter Code") {
            VStack(spacing: Space.s5) {
                Text("Type the code shown on your computer.")
                    .vaultType(.callout).themedForeground(.secondary)
                    .multilineTextAlignment(.center)

                TextField("XXXX-XXXX", text: Binding(
                    get: { QuickViewHumanCode.formatted(raw) },
                    set: { raw = QuickViewHumanCode.normalize($0) }))
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
                    let code = QuickViewHumanCode.normalize(raw)
                    dismiss()
                    onSubmit(code)
                } label: {
                    Text("Continue").frame(maxWidth: .infinity, minHeight: Metric.controlMedium)
                }
                .buttonStyle(.themedProminent)
                .disabled(raw.count < QuickViewHumanCode.length)
            }
            .padding(Space.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: raw) { showFormatError = false }
        }
    }
}
