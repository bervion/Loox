import SwiftUI

/// The hand-over confirmation (INV-08) as the system alert.
///
/// A hand-over cannot be undone, so it gets the platform's most deliberate
/// confirmation: a centered alert the owner has to answer. It replaced an
/// inline confirmation that opened at the bottom of the capability list,
/// often below the fold, where picking "Hand over" read as nothing happening.
///
/// Attach it to the sheet's form, never to a row. Its presentation then
/// outlives the menu that asked for it (see `InlineConfirm` for what happens
/// when a presentation's host goes away under it).
private struct ShareHandOverConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let pending: ShareCapabilityDraft.HandOver?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            Button("Hand over", role: .destructive) {
                Haptics.error()
                onConfirm()
            }
            Button("Cancel", role: .cancel, action: onCancel)
        } message: {
            Text(message)
        }
    }

    private var isPasskey: Bool {
        pending.map { PasskeySlot.isPasskeySlot($0.slot) } ?? false
    }

    private var title: LocalizedStringKey {
        isPasskey ? "Hand over this passkey?" : "Hand over this secret?"
    }

    /// What it means, that it is final, and the only real way back.
    private var message: LocalizedStringKey {
        isPasskey
            ? "They get their own copy and can use it without asking you. This can't be undone. Stopping sharing later only stops future updates. To lock them out later, delete this passkey at the website."
            : "They get their own copy and can use it without asking you. This can't be undone. Stopping sharing later only stops future updates. To lock them out later, set up two-factor again at the website."
    }
}

extension View {
    /// Asks before a parked hand-over (`ShareCapabilityDraft.pendingHandOver`)
    /// is confirmed. `isPresented` is its own flag rather than "a hand-over is
    /// pending": the pick stays parked while a confirmed hand-over publishes.
    func shareHandOverConfirmation(isPresented: Binding<Bool>,
                                   pending: ShareCapabilityDraft.HandOver?,
                                   onConfirm: @escaping () -> Void,
                                   onCancel: @escaping () -> Void) -> some View {
        modifier(ShareHandOverConfirmation(isPresented: isPresented, pending: pending,
                                           onConfirm: onConfirm, onCancel: onCancel))
    }
}
