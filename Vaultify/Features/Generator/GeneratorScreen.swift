import SwiftUI

/// The Generator tab.
struct GeneratorScreen: View {
    @State private var output = ""

    var body: some View {
        VaultSheetScaffold(title: "Generator",
                           leading: { EmptyView() },
                           trailing: { SheetDismissButton("Done") }) {
            PasswordGeneratorView(output: $output)
        }
    }
}

/// Generator presented as a sheet from the item editor's password field. The "Use" action
/// lives in the sheet header (top-right) instead of at the bottom of the form.
struct PasswordGeneratorSheet: View {
    let onUse: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var output = ""

    var body: some View {
        VaultSheetScaffold(title: "Generate Password", trailing: {
            Button {
                onUse(output)
                dismiss()
            } label: {
                Text("Use Password").fontWeight(.semibold)
            }
            .disabled(output.isEmpty)
        }) {
            PasswordGeneratorView(output: $output)
        }
    }
}
