#if os(iOS)
import SwiftUI
import UIKit

/// Compact-iOS unlocked shell as a UIKit container: a `UINavigationController`
/// whose root view controller hosts the SwiftUI `MainTabView`.
///
/// Keeping the SwiftUI `TabView` as the hosting controller's ROOT (not wrapped in
/// a SwiftUI `NavigationStack`) preserves the native iOS 26 search — `role:.search`
/// flies the field up over the keyboard — AND the Liquid Glass tab bar. Detail
/// pushes go onto the `UINavigationController` (see `AppNavigator`) so they cover
/// the tab bar with a native slide. Pure SwiftUI cannot do both at once; Telegram
/// uses this same nav-controller-over-tabs shape (it is UIKit too).
///
/// The nav controller's own bar stays hidden — each pushed destination draws its
/// own SwiftUI nav bar inside its hosting controller, so there is never a double
/// bar. The interactive edge swipe-back (which a hidden bar disables) is
/// re-enabled via the coordinator.
struct VaultUINavShell: UIViewControllerRepresentable {
    let env: AppEnvironment

    func makeUIViewController(context: Context) -> UINavigationController {
        let coordinator = context.coordinator
        let root = UIHostingController(
            rootView: MainTabView()
                .modifier(VaultRootEnvironment(env: env, navigator: coordinator.navigator))
        )
        let nav = UINavigationController(rootViewController: root)
        nav.setNavigationBarHidden(true, animated: false)
        nav.delegate = coordinator
        coordinator.rootViewController = root
        coordinator.navigator.navigationController = nav
        nav.interactivePopGestureRecognizer?.delegate = coordinator
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(env: env) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIGestureRecognizerDelegate {
        let navigator: AppNavigator
        weak var rootViewController: UIViewController?

        init(env: AppEnvironment) { navigator = AppNavigator(env: env) }

        /// The nav controller's own bar is never shown — the root is the tab bar
        /// (its own chrome) and every pushed screen draws its SwiftUI nav bar.
        func navigationController(_ navigationController: UINavigationController,
                                  willShow viewController: UIViewController, animated: Bool) {
            navigationController.setNavigationBarHidden(true, animated: false)
        }

        /// Re-enable the edge swipe-back that a hidden nav bar would disable, but
        /// only when there is something to pop (never on the tab-bar root).
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigator.navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
#endif
