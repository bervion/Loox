//
//  VaultifyApp.swift
//  Vaultify
//

import SwiftUI

@main
struct VaultifyApp: App {
    @State private var env = AppEnvironment()

    private var locale: Locale {
        switch env.settings.preferredLanguage {
        case "en": return Locale(identifier: "en")
        case "vi": return Locale(identifier: "vi")
        default: return .autoupdatingCurrent
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(env)
                .environment(\.locale, locale)
                .preferredColorScheme(env.settings.appearance.colorScheme)
        }
    }
}
