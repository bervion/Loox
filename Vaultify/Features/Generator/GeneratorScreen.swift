import SwiftUI

/// The Generator tab.
struct GeneratorScreen: View {
    var body: some View {
        VaultSheetScaffold(title: "Generator",
                           leading: { EmptyView() },
                           trailing: { SheetDismissButton("Done") }) {
            PasswordGeneratorView()
        }
    }
}

/// Generator presented as a sheet from the item editor's password field.
struct PasswordGeneratorSheet: View {
    let onUse: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VaultSheetScaffold(title: "Generate Password") {
            PasswordGeneratorView { password in
                onUse(password)
                dismiss()
            }
        }
    }
}
