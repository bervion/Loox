import SwiftUI

/// Chrome for REALTIME CloudKit actions (leave a share, revoke access):
/// they are only true once iCloud confirms them, so offline they must not
/// pretend to succeed — the control dims but stays tappable, and the tap
/// explains the situation instead of surfacing a raw CloudKit error.
/// Reachability is observable, so controls re-enable live when the network
/// returns. A satisfied path is a precondition, never an authorization
/// (INV-02) — the actual operation still validates against CloudKit.
extension View {
    /// Dim a realtime control while offline. Deliberately NOT `.disabled`:
    /// the tap must stay alive so the call site can present the notice.
    func onlineActionAppearance(online: Bool) -> some View {
        opacity(online ? 1 : 0.5)
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
