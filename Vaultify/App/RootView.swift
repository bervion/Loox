import SwiftUI

/// Top-level router. Switches between onboarding, the lock screen, and the
/// unlocked app, and enforces background privacy + auto-lock.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var obscured = false

    private enum Route: Equatable { case onboarding, locked, unlocked }

    private var route: Route {
        if !env.settings.onboardingCompleted { return .onboarding }
        return env.session.state == .unlocked ? .unlocked : .locked
    }

    var body: some View {
        ZStack {
            switch route {
            case .onboarding: OnboardingFlow()
            case .locked:
                // Controlled Reveal physics: unlocking blurs the locked world away so
                // the vault resolves behind it; locking contracts the lock screen back
                // in over the outgoing content (which lingers ≤0.35s beneath it —
                // comparable exposure to the previous crossfade; "Immediately"
                // auto-lock still swaps with no animation via withTransaction below).
                // zIndex keeps the lock ABOVE the app during both overlaps.
                LockScreen().transition(.controlledReveal).zIndex(1)
            case .unlocked: AdaptiveRootView().transition(.identity)
            }

            if obscured && env.settings.hideInAppSwitcher && route == .unlocked {
                PrivacyShield().transition(.opacity)
            }
        }
        // Purely presentational: the session flip already happened — this never gates
        // or delays auth. Reduce Motion collapses the route change to an instant swap.
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: route)
        .animation(.easeInOut(duration: 0.3), value: env.theme.active)
        .onChange(of: env.session.state) { _, newState in
            if newState == .unlocked {
                env.repository.reload()
                // Re-apply the last screen/tab/draft now that the vault (and its key) is
                // available — after reload so restored nav can resolve item ids.
                env.uiState.restore()
                env.syncNow()
            } else {
                env.repository.clear()
                // Shared projections hold decrypted values too — same lock
                // privacy model as the owned cache (the shell task rebuilds
                // them after the next unlock).
                env.sharedItems.wipe()
            }
        }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        .onChange(of: colorScheme) { _, scheme in env.theme.systemColorSchemeChanged(scheme) }
        .onAppear {
            env.theme.systemColorSchemeChanged(colorScheme)
            env.theme.applyInterfaceStyle()
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            obscured = false
            // Lock only if a *real* background stay met the auto-lock window. The Face ID
            // prompt drives `.inactive` (not `.background`), so its close doesn't lock here.
            env.session.lockIfBackgroundExpired()
            // The AutoFill extension may have created a login while we were away. Re-fetch so it
            // surfaces in the app, and push it to CloudKit (the extension itself can't sync).
            if env.session.state == .unlocked {
                env.repository.reload()
                env.syncNow()
                // Keep signed control-plane documents fresh without blocking unlock
                // or render (INV-CP-01/02). Fire-and-forget: the coordinator dedupes
                // the launch-after-unlock and foreground triggers into one request
                // per document family and applies its own freshness/backoff.
                Task {
                    await env.controlPlaneRefresher.refreshIfNeeded(trigger: .launchAfterUnlock)
                    await env.controlPlaneRefresher.refreshIfNeeded(trigger: .foreground)
                }
            }
        case .inactive:
            obscured = true
        case .background:
            obscured = true
            env.session.markBackgrounded()
            // Save the last screen/tab/draft while the Vault Key is still in memory —
            // MUST run before the lock below drops it (and tears down the UI).
            env.uiState.persist()
            // One timer governs leaving the app: "Immediately" drops the key right
            // here, with no animation — the lock screen should simply *be there* on
            // return, not cross-fade in from the unlocked UI. Any longer window keeps
            // the key so a quick copy-into-another-app round trip doesn't force a
            // re-auth; `lockIfBackgroundExpired` settles it on return.
            if env.settings.autoLock == .immediate {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { env.session.lock() }
            }
        @unknown default:
            break
        }
    }
}

/// Controlled Reveal route transition (see docs/design-guidelines.md → Loox Motion
/// Language): the concealed state is blurred, slightly enlarged, and transparent —
/// removal reads as the locked world dissolving to reveal the vault; insertion as
/// the lock settling back into place.
private struct ControlledRevealModifier: ViewModifier {
    let concealed: Bool

    func body(content: Content) -> some View {
        content
            .opacity(concealed ? 0 : 1)
            .blur(radius: concealed ? 10 : 0)
            .scaleEffect(concealed ? 1.05 : 1)
    }
}

extension AnyTransition {
    static var controlledReveal: AnyTransition {
        .modifier(active: ControlledRevealModifier(concealed: true),
                  identity: ControlledRevealModifier(concealed: false))
    }
}

/// Opaque overlay shown when the app is inactive/backgrounded to hide secrets.
/// Logo only — no wordmark — matching the splash logo size.
private struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            BrandLogoMark.hero
        }
    }
}
