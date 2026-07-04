//
//  VaultifyApp.swift
//  Vaultify
//

import SwiftUI

@main
struct VaultifyApp: App {
    @State private var env = AppEnvironment()
    // Receives CloudKit silent pushes for near-real-time sync (see AppPushDelegate).
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppPushDelegate.self) private var pushDelegate
    #elseif canImport(AppKit)
    @NSApplicationDelegateAdaptor(AppPushDelegate.self) private var pushDelegate
    #endif

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

        #if os(macOS)
        // Native Settings window (App menu → Settings…, ⌘,) — sidebar + detail panes.
        // Mirrors the main window's environment so themed controls and the in-app
        // language behave identically in both windows.
        Settings {
            MacSettingsView()
                .environment(env)
                .environment(env.uiState)
                .environment(\.locale, locale)
                .environment(\.appTheme, env.theme.active)
                .toggleStyle(.themed)
                .tint(env.theme.uiTint)
                .preferredColorScheme(env.theme.preferredColorScheme)
                .appFontScale(env.theme.settings.fontScale)
        }
        #endif
    }
}
