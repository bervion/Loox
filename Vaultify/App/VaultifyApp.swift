//
//  VaultifyApp.swift
//  Vaultify
//

import SwiftUI

@main
struct VaultifyApp: App {
    @State private var env = AppEnvironment()

    private var locale: Locale { appLocale(forCode: env.settings.preferredLanguage) }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(\.locale, locale)
                .environment(\.appTheme, env.theme.active)
                .tint(env.theme.accentColor)
                .preferredColorScheme(env.theme.preferredColorScheme)
                .appFontScale(env.theme.settings.fontScale)
                .environment(\.meshPhase, env.theme.meshPhase)
                .environment(\.meshAnimated, !env.theme.settings.reduceMotion)
        }
    }
}
