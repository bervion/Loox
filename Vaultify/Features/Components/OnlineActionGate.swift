import SwiftUI

/// Chrome for REALTIME CloudKit actions (leave a share, revoke access):
/// they are only true once iCloud confirms them, so offline they must not
/// pretend to succeed — the control dims but stays tappable, and the tap
/// explains the situation instead of surfacing a raw CloudKit error.
/// Reachability is observable, so controls re-enable live when the network
/// returns. A satisfied path is a precondition, never an authorization
/// (INV-02) — the actual operation still validates against CloudKit.
extension View {
    /// Mark a realtime control as needing internet. Deliberately NOT `.disabled`:
    /// the tap must stay alive so the call site can present the notice.
    ///
    /// This used to dim to `.opacity(0.5)`. That is the OS's DISABLED signal, so
    /// a control that was enabled and tappable read as dead — and it broke the
    /// project's own rule that a disabled control paints an opaque surface and
    /// never uses `.opacity` (see `ThemedButtonStyles`, `BrandCapsuleCTA`). The
    /// control now renders at full strength; the offline fact is carried by the
    /// notice the tap presents, plus a VoiceOver hint so the state is not
    /// sighted-only.
    func onlineActionAppearance(online: Bool) -> some View {
        accessibilityHint(online ? Text(verbatim: "") : Text("Needs an internet connection"))
    }

    /// Standard "this needs internet" notice for a gated realtime action.
    func offlineActionNotice(isPresented: Binding<Bool>,
                             message: LocalizedStringKey) -> some View {
        alert("No Internet Connection", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
