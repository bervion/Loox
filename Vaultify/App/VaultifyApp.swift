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
                .onOpenURL { url in
                    // 2FA setup from an otpauth:// link/QR → stash a draft login; presented once
                    // the vault is unlocked (see MainTabView).
                    if let draft = TOTPImport.draftLogin(from: url) { env.pendingTOTPImport = draft }
                }
                .environment(env)
                .environment(env.uiState)
                .environment(\.locale, locale)
                .environment(\.appTheme, env.theme.active)
                .toggleStyle(.themed)
                .tint(env.theme.uiTint)
                .preferredColorScheme(env.theme.preferredColorScheme)
                .appFontScale(env.theme.settings.fontScale)
                .environment(\.meshPhase, env.theme.meshPhase)
                .environment(\.meshAnimated, !env.theme.settings.reduceMotion)
        }
    }
}
