import SwiftUI

/// Top-level router. Switches between onboarding, the lock screen, and the
/// unlocked app, and enforces background privacy + auto-lock.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var obscured = false
    @State private var showSplash = true

    private enum Route: Equatable { case onboarding, locked, unlocked }

    private var route: Route {
        if !env.settings.onboardingCompleted { return .onboarding }
        return env.session.state == .unlocked ? .unlocked : .locked
    }

    var body: some View {
        ZStack {
            switch route {
            case .onboarding: OnboardingFlow()
            case .locked: LockScreen()
            case .unlocked: MainTabView()
            }

            if obscured && env.settings.hideInAppSwitcher && route == .unlocked {
                PrivacyShield().transition(.opacity)
            }

            if showSplash {
                SplashView().transition(.opacity).zIndex(2)
            }
        }
        .animation(.smooth(duration: 0.3), value: route)
        .animation(.easeOut(duration: 0.4), value: showSplash)
        .task {
            try? await Task.sleep(for: .milliseconds(750))
            showSplash = false
        }
        .onChange(of: env.session.state) { _, newState in
            if newState == .unlocked {
                env.repository.reload()
                env.syncNow()
            } else {
                env.repository.clear()
            }
        }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        .onChange(of: colorScheme) { _, scheme in env.theme.systemColorSchemeChanged(scheme) }
        .onAppear { env.theme.systemColorSchemeChanged(colorScheme) }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            obscured = false
            env.session.lockIfTimedOut()
        case .inactive:
            obscured = true
        case .background:
            obscured = true
            if env.settings.lockOnBackground { env.session.lock() }
        @unknown default:
            break
        }
    }
}

/// Opaque overlay shown when the app is inactive/backgrounded to hide secrets.
private struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 12) {
                PolarisIcon(Icons.lockFill, size: 44).foregroundStyle(.secondary)
                Text("Vaultify").font(.headline).foregroundStyle(.secondary)
            }
        }
    }
}
