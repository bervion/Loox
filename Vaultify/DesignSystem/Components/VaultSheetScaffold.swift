import SwiftUI

/// Base scaffold for modal sheets — one consistent header across the app.
///
/// A native inline (small, centred) nav title that never collapses, with leading + trailing
/// toolbar items (rendered as the OS's glass pills on iOS 26), over the caller's content on
/// the theme's grouped background. Use as the root view of any `.sheet { … }` content.
///
///     // Cancel + a trailing action:
///     VaultSheetScaffold(title: "Spaces", trailing: {
///         Button { … } label: { PolarisIcon(Icons.add, size: 18) }
///     }) { List { … } }
///
///     // Read-only viewer — Done on the right:
///     VaultSheetScaffold(title: "Generator",
///                        leading: { EmptyView() },
///                        trailing: { SheetDismissButton("Done") }) { … }
///
/// Pass `title: nil` to hide the title — recommended once a sheet carries **3+ toolbar
/// actions** (e.g. Cancel + Edit + Save), where a centre title would crowd the bar.
struct VaultSheetScaffold<Leading: View, Trailing: View, Content: View>: View {
    let title: LocalizedStringResource?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        NavigationStack {
            content()
                .themedFormBackground()
                .themedColorScheme()
                // The root `.tint` doesn't reliably reach presented sheets, so re-apply the
                // control tint here (accent in light, white in dark) for sheet content too.
                .tint(env.theme.uiTint)
                .navigationTitle(titleText)
                .platformNavigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .platformTopBarLeading) { leading() }
                    ToolbarItemGroup(placement: .platformPrimaryAction) { trailing() }
                }
        }
    }

    private var titleText: Text {
        guard let title else { return Text(verbatim: "") }
        return Text(title.inAppLocalized)
    }
}

// MARK: - Convenience inits (default leading = Cancel)

extension VaultSheetScaffold where Leading == SheetDismissButton {
    /// Cancel (leading) + a trailing action.
    init(
        title: LocalizedStringResource?,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, leading: { SheetDismissButton() }, trailing: trailing, content: content)
    }
}

extension VaultSheetScaffold where Leading == SheetDismissButton, Trailing == EmptyView {
    /// Cancel (leading) only.
    init(
        title: LocalizedStringResource?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, leading: { SheetDismissButton() }, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Dismiss button

/// A toolbar button that dismisses the sheet. Defaults to "Cancel" (use "Done"/"Close" for
/// read-only viewers). Reads `\.dismiss`, so it works wherever it's placed in the toolbar.
struct SheetDismissButton: View {
    var label: LocalizedStringResource = "Cancel"
    @Environment(\.dismiss) private var dismiss

    init(_ label: LocalizedStringResource = "Cancel") { self.label = label }

    var body: some View {
        Button { dismiss() } label: { Text(label) }
    }
}
