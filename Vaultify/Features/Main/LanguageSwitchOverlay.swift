import SwiftUI

/// Full-screen branded cover shown while the in-app language is applied (see
/// `AppNavigator.switchLanguage`). The pushed Settings stack is rebuilt fresh
/// behind this cover — a detached hosting controller's nav-bar title otherwise
/// caches the old language — so the swap is masked by the same dots-swirl mark
/// the QR pairing screen uses, then it fades away to reveal Settings re-localized.
struct LanguageSwitchOverlay: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        ZStack {
            // Opaque — this cover fully hides the rebuild happening beneath it.
            Color(rgb: env.theme.active.groupedBackground)
                .ignoresSafeArea()

            VStack(spacing: Space.s6) {
                LooxSwirlAnimationView(mode: .reveal)
                    .frame(width: 140, height: 140)

                Text("Changing language")
                    .vaultType(.subhead)
                    .themedForeground(.secondary)
            }
        }
    }
}
