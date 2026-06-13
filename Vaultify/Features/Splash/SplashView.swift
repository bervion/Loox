import SwiftUI

/// Cold-start splash: the app logo + name over the adaptive launch background.
/// Matches the static launch screen so the hand-off is seamless, then fades to
/// reveal the app (RootView dismisses it after a brief delay).
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()

            VStack(spacing: 18) {
                Image("AppLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 104, height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 8)

                Text("Vaultify")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { appeared = true }
        }
    }
}
