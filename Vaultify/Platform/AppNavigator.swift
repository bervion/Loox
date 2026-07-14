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
        let hosted = NavigationStack {
            dest
                // Marks this as a navigator-push ROOT: its own `dismiss()` can't
                // pop the UINavigationController, so self-dismissing screens pop
                // via the navigator instead. Anything pushed deeper inside this
                // stack resets the flag (see `vaultNavigationDestinations`).
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
        .modifier(VaultRootEnvironment(env: env, navigator: self, rebuildsOnLanguageChange: true))
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
}

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
