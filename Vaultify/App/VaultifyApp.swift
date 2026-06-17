//
//  VaultifyApp.swift
//  Vaultify
//

import SwiftUI
import UIKit

@main
struct VaultifyApp: App {
    @State private var env = AppEnvironment()

    init() {
        // Slightly smaller native large title (closer to the DS screen-title scale,
        // 34 → 30) while keeping the system large-title → inline collapse on scroll.
        // Backgrounds keep system defaults: transparent at the top, material once
        // content scrolls under the inline bar.
        let largeFont = UIFont.systemFont(ofSize: 30, weight: .bold)
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.largeTitleTextAttributes[.font] = largeFont
        let edge = UINavigationBarAppearance()
        edge.configureWithTransparentBackground()
        edge.largeTitleTextAttributes[.font] = largeFont
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = edge
    }

    private var locale: Locale { appLocale(forCode: env.settings.preferredLanguage) }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(\.locale, locale)
                .environment(\.appTheme, env.theme.active)
                .toggleStyle(.themed)
                .tint(env.theme.accentColor)
                .preferredColorScheme(env.theme.preferredColorScheme)
                .appFontScale(env.theme.settings.fontScale)
                .environment(\.meshPhase, env.theme.meshPhase)
                .environment(\.meshAnimated, !env.theme.settings.reduceMotion)
        }
    }
}
