import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Bridges SwiftUI screens to the compact-iOS UIKit navigation shell
/// (`VaultUINavShell`). Screens push detail destinations onto the shared
/// `UINavigationController`, so the push covers the tab bar with a native slide —
/// the SwiftUI equivalent (hiding the tab bar per push) animates poorly on the
/// iOS 26 beta. Telegram uses the same nav-controller-over-tabs shape.
///
/// Each pushed destination becomes the root of its OWN SwiftUI `NavigationStack`,
/// so the detail's internal navigation (folder → item, Settings → General) stays
/// ordinary SwiftUI and needs no conversion — only the first hop out of a tab is
/// bridged here.
///
/// Injected into the environment on ALL platforms so shared screens can reference
/// it, but every method is a no-op off iOS; the iPad/Mac sidebar leaves it nil and
/// keeps its SwiftUI `NavigationStack` paths (screens fall back to those).
@Observable
final class AppNavigator {
    #if os(iOS)
    /// Weak — the navigation controller owns the shell, not the reverse.
    weak var navigationController: UINavigationController?
    #endif

    /// Captured so every pushed hosting controller re-injects the full app
    /// environment (see `VaultRootEnvironment`).
    private let env: AppEnvironment

    init(env: AppEnvironment) { self.env = env }

    /// Push a detail destination full-screen (covering the tab bar). The
    /// destination is hosted as the root of a fresh `NavigationStack` carrying the
    /// shared push destinations, plus a leading Back button that pops this
    /// controller (the stack root has no automatic one).
    func push<Destination: View>(@ViewBuilder _ destination: () -> Destination) {
        #if os(iOS)
        guard let navigationController else { return }
        let dest = destination()
        let hosted = NavigatorPushHost(env: env, navigator: self) {
            NavigationStack {
                dest
                    // Marks this as a navigator-push ROOT: its own `dismiss()`
                    // can't pop the UINavigationController, so self-dismissing
                    // screens pop via the navigator instead. Anything pushed
                    // deeper inside this stack resets the flag (see
                    // `vaultNavigationDestinations`).
                    .environment(\.isNavigatorRoot, true)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { [weak self] in self?.pop() } label: {
                                PolarisIcon(Icons.chevronLeft)
                            }
                            .accessibilityLabel(Text("Back"))
                        }
                    }
                    .vaultNavigationDestinations()
            }
        }
        let controller = UIHostingController(rootView: hosted)
        navigationController.pushViewController(controller, animated: true)
        #endif
    }

    func pop() {
        #if os(iOS)
        navigationController?.popViewController(animated: true)
        #endif
    }

    func popToRoot() {
        #if os(iOS)
        navigationController?.popToRootViewController(animated: true)
        #endif
    }

    /// Apply an in-app language and land the user back on a freshly rendered
    /// Settings, masked by a branded cover. A pushed screen's nav-bar title caches
    /// the old language inside its detached hosting controller, so rather than
    /// re-localize it in place we REBUILD: present an opaque cover, swap the
    /// language + pop to a fresh Settings beneath it, then fade the cover out to
    /// reveal Settings fully re-localized. Falls back to a plain swap off iOS.
    func switchLanguage(to language: String) {
        #if os(iOS)
        guard let navigationController else {
            env.settings.preferredLanguage = language
            return
        }
        let overlay = UIHostingController(
            rootView: LanguageSwitchOverlay().modifier(VaultRootEnvironment(env: env, navigator: self)))
        overlay.modalPresentationStyle = .overFullScreen
        overlay.modalTransitionStyle = .crossDissolve
        // The SwiftUI overlay paints its own opaque themed background; keep the
        // host clear so the cross-dissolve shows only that (no system-white flash).
        overlay.view.backgroundColor = .clear
        navigationController.present(overlay, animated: true) { [weak self, weak navigationController, weak overlay] in
            guard let self, let navigationController else { return }
            self.env.settings.preferredLanguage = language
            navigationController.popToRootViewController(animated: false)
            self.push { SettingsScreen() }
            Task { @MainActor in
                // Hold for one dots-swirl reveal cycle (~1.6s), then fade out.
                try? await Task.sleep(for: .milliseconds(1600))
                overlay?.dismiss(animated: true)
            }
        }
        #else
        env.settings.preferredLanguage = language
        #endif
    }
}

#if os(iOS)
/// Hosts a navigator-pushed screen. A DETACHED `UIHostingController` does not
/// re-localize live on an in-app language switch — its nav title / labels go
/// stale. Reading `preferredLanguage` in THIS View body (which then re-applies
/// the shared environment, so `\.locale` is refreshed) forces the whole pushed
/// subtree to re-render in place. A `.id`-based rebuild would fix localization
/// too, but at the cost of popping the pushed navigation back to its root.
private struct NavigatorPushHost<Content: View>: View {
    let env: AppEnvironment
    let navigator: AppNavigator
    @ViewBuilder var content: Content

    var body: some View {
        // Observe the language here so a switch re-runs this body and re-applies
        // the environment chain (fresh `\.locale`) to the pushed content.
        let _ = env.settings.preferredLanguage
        content.modifier(VaultRootEnvironment(env: env, navigator: navigator))
    }
}
#endif

private struct IsNavigatorRootKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True only for the ROOT view of an `AppNavigator` push (compact-iOS UIKit
    /// shell). Such a root cannot self-dismiss via SwiftUI `dismiss()` — a nested
    /// `NavigationStack` root swallows it — so it pops the shell's
    /// `UINavigationController`. Defaults false: nested pushes inside the stack,
    /// modal presentations, and the iPad/Mac sidebar all pop via `dismiss()`.
    var isNavigatorRoot: Bool {
        get { self[IsNavigatorRootKey.self] }
        set { self[IsNavigatorRootKey.self] = newValue }
    }
}
