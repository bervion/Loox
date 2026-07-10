import SwiftUI

/// Deferred zoom navigation (Design DNA #5: "search→detail shared visual continuity").
/// A tapped row zooms into its destination on iOS 18+ (`.navigationTransition(.zoom)`);
/// iOS 17.6 falls back to a plain push automatically — the API simply doesn't exist there.
///
/// The shared `Namespace.ID` must live in a view that is an ancestor of BOTH the row
/// (`.matchedTransitionSource`) and the pushed destination (`.navigationTransition`). Since
/// `vaultNavigationDestinations()` is reused by several stacks (Home, Items, Search, Archive,
/// Trash, sidebar…) but only some of them own a zoom namespace, this is threaded through an
/// `EnvironmentKey` defaulting to `nil` — every call site stays optional-safe: no namespace
/// injected means no transition, just the ordinary push.
private struct VaultZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// Non-nil only in stacks that opt in (currently Search). Inject via
    /// `.environment(\.vaultZoomNamespace, someNamespace)` on the NavigationStack's content.
    var vaultZoomNamespace: Namespace.ID? {
        get { self[VaultZoomNamespaceKey.self] }
        set { self[VaultZoomNamespaceKey.self] = newValue }
    }
}

/// Applies `.matchedTransitionSource` to a row when a zoom namespace is present. No-op
/// (plain row) under Reduce Motion, pre-iOS-18, or when no namespace was injected — every
/// Loox motion effect must collapse to an instant swap under Reduce Motion (Design DNA #5).
struct ZoomTransitionSource: ViewModifier {
    let id: AnyHashable
    @Environment(\.vaultZoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace, !reduceMotion {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Applies `.navigationTransition(.zoom)` to a pushed destination when a zoom namespace is
/// present, matching the `id` a `ZoomTransitionSource` row registered. Same collapse rules
/// as `ZoomTransitionSource`.
struct ZoomTransitionDestination: ViewModifier {
    let id: AnyHashable
    @Environment(\.vaultZoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let namespace, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            content
        }
    }
}
