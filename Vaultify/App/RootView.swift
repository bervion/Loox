import SwiftUI

/// Top-level router. Switches between onboarding, the lock screen, and the
/// unlocked app, and enforces background privacy + auto-lock.
struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var obscured = false
    /// Success flourish: the memoji wink shown over the freshly-unlocked app
    /// (set by the lock screen on a successful unlock, cleared when it ends).
    @State private var celebrateUnlock = false
    /// True when the lock screen's absorb already centred the mark (manual
    /// password unlock) — the wink then starts at the centre instead of gliding
    /// down from the biometric resting spot.
    @State private var celebrateFromCenter = false

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
                LockScreen(onUnlockSuccess: { fromCenter in
                    if !reduceMotion {
                        celebrateFromCenter = fromCenter
                        celebrateUnlock = true
                    }
                })
                    .transition(.controlledReveal).zIndex(1)
            case .unlocked:
                // The tutorial host wraps the unlocked app only: it reads the
                // anchors those screens publish, and staying inside this branch
                // keeps every overlay off the lock screen and onboarding.
                AdaptiveRootView()
                    .tutorialHost(env.tutorial)
                    .transition(.identity)
            }

            if obscured && env.settings.hideInAppSwitcher && route == .unlocked {
                PrivacyShield().transition(.opacity)
            }

            // Plays over the freshly-unlocked app, then hands off. Sits above
            // everything so it also masks the lock→vault reveal underneath.
            if celebrateUnlock {
                LooxWinkView(onFinished: { celebrateUnlock = false },
                             startsCentered: celebrateFromCenter)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: celebrateUnlock)
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
                // Same control-plane freshness nudge as the foreground path below —
                // without it, a password unlock that never left `.active` (no
                // scene-phase change) ran the whole session on stale documents.
                if !env.uiTestConfiguration.isEnabled {
                    Task { await env.controlPlaneRefresher.refreshIfNeeded(trigger: .launchAfterUnlock) }
                }
            } else {
                env.repository.clear()
                // Shared projections hold decrypted values too — same lock
                // privacy model as the owned cache (the shell task rebuilds
                // them after the next unlock).
                env.sharedItems.wipe()
            }
        }
        // Connectivity regained → push whatever was created or edited offline
        // (items, Spaces, personas) without waiting for the next foreground.
        // The sync coordinator dedupes, so a flappy network stays cheap.
        .onChange(of: env.reachability.hasSatisfiedNetworkPath) { _, satisfied in
            if satisfied, env.session.state == .unlocked {
                env.syncNow()
            }
        }
        // Another device asked this one to sign out (Profile › Devices › Log Out
        // Device) — the marker arrives with any sync, including a silent push.
        .onReceive(NotificationCenter.default.publisher(for: .vaultRemoteSignOut)) { _ in
            env.handleRemoteSignOut()
        }
        .alert("This device was signed out", isPresented: Binding(
            get: { env.remoteSignOutNotice },
            set: { env.remoteSignOutNotice = $0 })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Another device removed this device from the vault. Loox data on this device was erased. Your items remain in the vault.")
        }
        .onChange(of: env.settings.onboardingCompleted) { _, completed in
            // Safety net for onboarding paths that skip the ChooseTheme step (e.g.
            // restoring an existing vault via JoinVaultFlow) — release the
            // fresh-install forced-light gate the moment onboarding completes, even
            // without an explicit appearance pick. A no-op if already released.
            if completed { env.markAppearanceChosen() }
        }
        .onChange(of: scenePhase) { _, phase in handleScenePhase(phase) }
        .onChange(of: colorScheme) { _, scheme in env.theme.systemColorSchemeChanged(scheme) }
        .onAppear {
            env.theme.systemColorSchemeChanged(colorScheme)
            env.theme.applyInterfaceStyle()
            // Owner-reported: a device could render dark on a light theme until
            // a manual dark→light toggle. Windows created after this pass never
            // received the override — re-apply as each becomes visible.
            PlatformAppearance.reapplyOnNewWindows { env.theme.applyInterfaceStyle() }
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            obscured = false
            // Belt to the window observer's braces: whatever attached or
            // changed while inactive, the forced appearance is consistent the
            // moment the app is frontmost again.
            env.theme.applyInterfaceStyle()
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
                if !env.uiTestConfiguration.isEnabled {
                    Task {
                        await env.controlPlaneRefresher.refreshIfNeeded(trigger: .launchAfterUnlock)
                        await env.controlPlaneRefresher.refreshIfNeeded(trigger: .foreground)
                    }
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
/// Uses the lightweight breathing symbol (no memoji players) — this mounts on
/// every inactivity transition, so it must stay cheap and appear instantly.
private struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            // Same 132pt as the lock screen's mark, both dead-centre — the
            // shield → lock hand-off reads as one continuous logo.
            LooxLogoBreatheView(ready: true)
                .frame(width: 132, height: 132)
        }
    }
}
