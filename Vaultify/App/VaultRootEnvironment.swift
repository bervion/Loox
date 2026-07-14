import SwiftUI

/// The full app-environment chain in one place, so the root window AND every
/// UIKit-pushed hosting controller (see `AppNavigator` / `VaultUINavShell`)
/// inject an identical environment.
///
/// A `UIHostingController` created imperatively starts a FRESH SwiftUI
/// environment — the outer window's environment does not cross the UIKit
/// boundary — so a pushed detail screen would crash on any object it misses.
/// Centralizing the chain here means the compact-iOS shell and the SwiftUI
/// root window can never drift apart.
struct VaultRootEnvironment: ViewModifier {
    let env: AppEnvironment
    #if os(iOS)
    /// Present only inside the compact-iOS UIKit shell; nil on the iPad/Mac
    /// sidebar and the lock screen (those use ordinary SwiftUI navigation).
    var navigator: AppNavigator? = nil
    #endif

    func body(content: Content) -> some View {
        let base = content
            .environment(env)
            .environment(env.uiState)
            .environment(\.locale, appLocale(forCode: env.settings.preferredLanguage))
            .environment(\.appTheme, env.theme.active)
            .toggleStyle(.themed)
            .tint(Color.primary)
            .preferredColorScheme(env.theme.preferredColorScheme)
            .appFontScale(env.theme.settings.fontScale)
            .environment(\.meshPhase, env.theme.meshPhase)
            .environment(\.meshAnimated, !env.theme.settings.reduceMotion)
        #if os(iOS)
        return base.environment(navigator)
        #else
        return base
        #endif
    }
}
