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
        mainWindow

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

    private var mainWindow: some Scene {
        // NOTE: no hiddenTitleBar — combined with a hidden window toolbar it took the
        // traffic lights down with it. The Mac shell puts search/New Item INTO the
        // system unified toolbar instead (see MacRootView), which is also how the
        // reference app builds its header row.
        WindowGroup { rootContent }
    }

    private var rootContent: some View {
        RootView()
                .onOpenURL { url in
                    // 2FA setup from an otpauth:// link/QR → stash a draft login; presented once
                    // the vault is unlocked (see MainTabView).
                    if let draft = TOTPImport.draftLogin(from: url) { env.pendingTOTPImport = draft }
                }
                // Universal Link: share-invite (invite.looxpassword.com/i/<token>#k=…).
                // Resolve + accept in background; the unlocked shell picks the
                // acceptance up via the standard breadcrumb/resume flow.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL,
                          InviteLinkService.isInviteLink(url) else { return }
                    Task { try? await env.inviteLinks.acceptInvite(from: url) }
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
