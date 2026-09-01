import SwiftUI

/// Two-step confirmation for a destructive action **inside a sheet**.
///
/// `confirmationDialog` cannot be used there. A dialog presented from a view that
/// lives inside a sheet makes SwiftUI tear the sheet's content down: the sheet's
/// `@State` resets and the button's action closure never runs. Measured on
/// 2026-09-01 — a revoke tapped through the dialog produced no request at all
/// (server logs showed zero), while the identical call made straight from the
/// swipe action succeeded. The same dialog code works fine on a pushed screen
/// (`PersonaAliasesScreen`), which is why the pattern looks safe until it is used
/// one presentation deeper.
///
/// Confirming inline keeps the deliberate second step without a second
/// presentation, so it cannot regress the same way.
///
/// Sits directly in the list row or section it guards; the caller owns the
/// pending state and clears it in both closures.
struct InlineConfirm: View {
    /// What the user is agreeing to. Reuse the copy the dialog used — it is
    /// already written and translated.
    let message: LocalizedStringKey
    /// Destructive button label, e.g. "Revoke Link".
    let confirmTitle: LocalizedStringKey
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text(message)
                .vaultType(.footnote)
                .themedForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Side by side: the destructive choice must never be the only
            // thing under the thumb after a swipe already committed one step.
            HStack(spacing: Space.s3) {
                Button {
                    Haptics.tap()
                    onCancel()
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedTinted)

                Button(role: .destructive) {
                    Haptics.error()
                    onConfirm()
                } label: {
                    Text(confirmTitle).frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedDestructive)
            }
        }
        .padding(.vertical, Space.s2)
        .transition(.opacity)
    }
}
