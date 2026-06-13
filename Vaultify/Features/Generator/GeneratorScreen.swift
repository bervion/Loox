import SwiftUI

/// The Generator tab.
struct GeneratorScreen: View {
    var body: some View {
        NavigationStack {
            PasswordGeneratorView()
                .navigationTitle("Generator")
        }
    }
}

/// Generator presented as a sheet from the item editor's password field.
struct PasswordGeneratorSheet: View {
    let onUse: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PasswordGeneratorView { password in
                onUse(password)
                dismiss()
            }
            .navigationTitle("Generate Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
