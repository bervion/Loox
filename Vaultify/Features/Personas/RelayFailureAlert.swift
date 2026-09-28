import SwiftUI

/// The one recovery a relay failure lets the user choose: resetting Private
/// Email when this vault can't open its escrowed key
/// (`RelayService.Failure.principalFromAnotherVault`, typically after an app
/// reinstall). The answer comes back as alert copy, so every surface reports it
/// the way it reported the failure.
@MainActor enum PrivateEmailReset {
    struct Result: Equatable {
        var title: String
        var message: String
        /// The reset ended in the same failure (another device changed the
        /// escrow meanwhile), so the alert offers the reset again.
        var offersReset = false
    }

    static func run(using relay: RelayService) async -> Result {
        do {
            try await relay.resetPrincipal()
            Haptics.success()
            // Neutral on purpose: the re-check may have found the escrow readable
            // again, in which case nothing was replaced.
            return Result(title: appString("Private Email is ready"),
                          message: appString("You can try again now."))
        } catch let failure as RelayService.Failure {
            Haptics.error()
            return Result(title: failure.userTitle, message: failure.userMessage,
                          offersReset: failure.offersPrivateEmailReset)
        } catch {
            Haptics.error()
            return Result(title: appString("Couldn’t reach the relay"),
                          message: appString("Check your connection and iCloud, then try again."))
        }
    }
}

extension View {
    /// The alert every Private Email surface uses for a relay failure: "OK" on
    /// its own, except when this vault can't open Private Email's key. Then the
    /// user may deliberately reset Private Email, or cancel.
    func relayFailureAlert(title: String, message: String?, isPresented: Binding<Bool>,
                           offersReset: Bool, reset: @escaping () -> Void) -> some View {
        alert(Text(verbatim: title), isPresented: isPresented) {
            if offersReset {
                Button("Reset Private Email", role: .destructive, action: reset)
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(verbatim: message ?? "")
        }
    }

    /// `relayFailureAlert` for a verification controller's outcome. The three
    /// verification surfaces share it, so none of them can drift again.
    func relayOutcomeAlert(_ verification: ForwardingInboxVerification,
                           relay: RelayService) -> some View {
        relayFailureAlert(title: verification.outcome?.title ?? "",
                          message: verification.outcome?.body,
                          isPresented: Binding(get: { verification.outcome != nil },
                                               set: { if !$0 { verification.outcome = nil } }),
                          offersReset: verification.outcome?.offersReset ?? false) {
            Task { await verification.resetPrivateEmail(relay: relay) }
        }
    }
}
