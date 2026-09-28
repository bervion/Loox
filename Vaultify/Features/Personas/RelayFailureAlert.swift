import SwiftUI

/// The one recovery a relay failure lets the user choose: replacing a Private
/// Email identity this vault can't open (`RelayService.Failure
/// .principalFromAnotherVault`, typically after an app reinstall). The answer
/// comes back as alert copy, so every surface reports it the way it reported
/// the failure.
@MainActor enum RelayIdentityRecovery {
    struct Result: Equatable {
        var title: String
        var message: String
    }

    static func startNewIdentity(using relay: RelayService) async -> Result {
        do {
            try await relay.startNewPrincipal()
            Haptics.success()
            return Result(title: appString("New Private Email identity ready"),
                          message: appString("You can try again now."))
        } catch let failure as RelayService.Failure {
            Haptics.error()
            return Result(title: failure.userTitle, message: failure.userMessage)
        } catch {
            Haptics.error()
            return Result(title: appString("Couldn’t reach the relay"),
                          message: appString("Check your connection and iCloud, then try again."))
        }
    }
}

extension View {
    /// The alert every Private Email surface uses for a relay failure: "OK" on
    /// its own, except when this vault can't open the Private Email identity.
    /// Then the user may deliberately start a new one, or cancel.
    func relayFailureAlert(title: String, message: String?, isPresented: Binding<Bool>,
                           offersNewIdentity: Bool,
                           startNewIdentity: @escaping () -> Void) -> some View {
        alert(Text(verbatim: title), isPresented: isPresented) {
            if offersNewIdentity {
                Button("Start New Identity", role: .destructive, action: startNewIdentity)
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(verbatim: message ?? "")
        }
    }
}
