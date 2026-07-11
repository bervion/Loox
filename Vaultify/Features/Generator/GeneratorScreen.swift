import SwiftUI

/// The Generator tab.
struct GeneratorScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var output = ""

    var body: some View {
        // No title; leading = X dismiss. The trailing regenerate button comes
        // from PasswordGeneratorView's own toolbar (no "use" action on this tab).
        VaultSheetScaffold(
            title: nil,
            leading: {
                Button { dismiss() } label: { PolarisIcon(Icons.close, size: Metric.iconInline) }
                    .accessibilityLabel(Text("Close"))
            },
            trailing: { EmptyView() }
        ) {
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
        // Leading = an X (icon) dismiss; the regenerate + use (checkmark) group
        // lives in PasswordGeneratorView's own trailing toolbar.
        VaultSheetScaffold(
            title: nil,
            leading: {
                Button { dismiss() } label: { PolarisIcon(Icons.close, size: Metric.iconInline) }
                    .accessibilityLabel(Text("Cancel"))
            },
            trailing: { EmptyView() }
        ) {
            PasswordGeneratorView(output: $output, onUse: onUse)
        }
    }
}
