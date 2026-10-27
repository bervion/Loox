import SwiftUI

/// The hand-over confirmation (INV-08) as a step that owns the whole sheet.
///
/// It replaces an `InlineConfirm` that opened at the bottom of the capability
/// list. On a tall form that was below the fold, so picking "Hand over" read as
/// nothing happening. A system dialog is not an option inside a sheet (it tears
/// the sheet's state down before its action runs, see `InlineConfirm`) and it
/// could not show the publish or its outcome anyway. Swapping the sheet's
/// content keeps one presentation and gives the decision, the wait and the
/// result the same surface.
struct ShareHandOverConfirmView: View {
    enum Kind: Equatable {
        case secret, passkey

        init(slot: String) {
            self = PasskeySlot.isPasskeySlot(slot) ? .passkey : .secret
        }
    }

    enum Phase: Equatable {
        case confirm
        case working
        case done
        case failed(String)
    }

    let kind: Kind
    var phase: Phase = .confirm
    /// Confirming also publishes the owner's other edits on the sheet.
    var appliesOtherChanges = false
    let onConfirm: () -> Void
    let onCancel: () -> Void
    var onDone: () -> Void = {}

    var body: some View {
        switch phase {
        case .confirm:
            VaultStatusScreen(
                icon: Icons.alert, tint: .warning, title: title,
                message: .key("They get their own copy and can use it without asking you."),
                feature: { consequences },
                primary: .init(title: "Hand over", destructive: true) {
                    Haptics.error()
                    onConfirm()
                },
                secondary: .init(title: "Cancel") {
                    Haptics.tap()
                    onCancel()
                })
        case .working:
            VaultStatusScreen(title: "Handing over", busy: true)
        case .done:
            VaultStatusScreen(
                icon: Icons.checkCircle, tint: .success,
                title: kind == .secret ? "Secret handed over" : "Key handed over",
                message: .key("It reaches their device on its next refresh."),
                primary: .init(title: "Done", action: onDone))
        case .failed(let message):
            VaultStatusScreen(
                icon: Icons.alert, tint: .destructive, title: "Couldn't hand over",
                message: .verbatim(message),
                primary: .init(title: "Try again", action: onConfirm),
                secondary: .init(title: "Cancel", action: onCancel))
        }
    }

    private var title: LocalizedStringKey {
        kind == .secret ? "Hand over this secret?" : "Hand over this passkey?"
    }

    /// What the owner is agreeing to, one fact per line: the limit first, then
    /// the only real way back.
    private var consequences: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            point(Icons.lock, "This can't be undone. Stopping sharing later only stops future updates.")
            point(kind == .secret ? Icons.key : Icons.passkey,
                  kind == .secret
                      ? "To lock them out later, set up two-factor again at the website."
                      : "To lock them out later, delete this passkey at the website.")
            if appliesOtherChanges {
                point(Icons.info, "Your other changes on this screen are applied too.")
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }

    private func point(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VaultIcon(icon, size: Metric.iconInline)
                .themedForeground(.iconSecondary)
            Text(text)
                .vaultType(.callout)
                .themedForeground(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}
