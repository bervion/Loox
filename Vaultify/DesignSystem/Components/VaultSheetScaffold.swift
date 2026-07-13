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
        #if os(macOS)
        // macOS: sheets size to their content's ideal size (a bare List collapses to a
        // sliver) and `NavigationStack` toolbars inside sheets render unreliably — the
        // dismiss button can simply not appear, leaving the sheet impossible to close.
        // Render an explicit header row + an explicit frame instead; Esc also closes
        // via `SheetDismissButton`'s cancel shortcut.
        VStack(spacing: 0) {
            macHeader
            Divider()
            content()
                .themedFormBackground()
        }
        .background(Color(rgb: env.theme.active.groupedBackground))
        .themedColorScheme()
        .tint(Color.primary)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 460, idealHeight: 620)
        #else
        NavigationStack {
            content()
                .themedFormBackground()
                .themedColorScheme()
                // The root `.tint` doesn't reliably reach presented sheets, so re-apply the
                // control tint here (accent in light, white in dark) for sheet content too.
                .tint(Color.primary)
                .navigationTitle(titleText)
                .platformNavigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .platformTopBarLeading) { leading() }
                    ToolbarItemGroup(placement: .platformPrimaryAction) { trailing() }
                }
        }
        #endif
    }

    #if os(macOS)
    /// Explicit sheet header: leading actions — centred title — trailing actions.
    /// Borderless buttons (accent text / clean glyphs) match macOS sheet-bar idiom.
    private var macHeader: some View {
        ZStack {
            titleText
                .vaultType(.headline)
                .themedForeground()
                .lineLimit(1)
            HStack {
                HStack(spacing: Space.s2) { leading() }
                Spacer()
                HStack(spacing: Space.s2) { trailing() }
            }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Space.s4)
        .frame(height: 44)
        .background(Color(rgb: env.theme.active.groupedBackground))
    }
    #endif

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
            // Esc closes the sheet (macOS convention; also hardware keyboards on iPad).
            .keyboardShortcut(.cancelAction)
    }
}
