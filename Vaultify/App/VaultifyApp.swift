//
//  VaultifyApp.swift
//  Vaultify
//

import SwiftUI

@main
struct VaultifyApp: App {
    @State private var env: AppEnvironment
    /// Localized failure from an invite universal link (expired/invalid).
    @State private var inviteError: String?
    /// Acceptance succeeded — tell the user where to look (the accept itself
    /// is silent/native by design; silence reads as "nothing happened").
    @State private var inviteAccepted = false
    @State private var inviteInFlight = false
    // Receives CloudKit silent pushes for near-real-time sync (see AppPushDelegate).
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppPushDelegate.self) private var pushDelegate
    #elseif canImport(AppKit)
    @NSApplicationDelegateAdaptor(AppPushDelegate.self) private var pushDelegate
    #endif

    private var locale: Locale { appLocale(forCode: env.settings.preferredLanguage) }

    init() {
        let uiTestConfiguration = UITestConfiguration.current
        _env = State(initialValue: AppEnvironment(uiTestConfiguration: uiTestConfiguration))
        // Providers must exist before the first event. Runs fine without a
        // GoogleService-Info.plist — the engine then stays dark (see
        // `FirebaseAnalyticsProvider.bootstrapped`).
        if !uiTestConfiguration.isEnabled, !CloudSyncService.isHostingUnitTests {
            AnalyticsEngine.bootstrap()
        }
    }

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
                .tint(Color.primary)
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

    /// One path for warm-tap and cold-launch invite links; the buffer is
    /// cleared here so a handled link can't be re-processed by the drain.
    private func handleInviteLink(_ url: URL) {
        guard !inviteInFlight else { return }
        inviteInFlight = true
        PendingInviteLink.url = nil
        Task {
            defer { inviteInFlight = false }
            do {
                try await env.inviteLinks.acceptInvite(from: url)
                inviteAccepted = true
            } catch { inviteError = error.localizedDescription }
        }
    }

    private var rootContent: some View {
        RootView()
                .transaction { transaction in
                    if env.uiTestConfiguration.isEnabled { transaction.animation = nil }
                }
                .onOpenURL { url in
                    // 2FA setup from an otpauth:// link/QR → stash a draft login; presented once
                    // the vault is unlocked (see MainTabView).
                    if let draft = TOTPImport.draftLogin(from: url) {
                        env.pendingTOTPImport = draft
                    } else if let itemID = SharedItemDeepLink.itemID(from: url) {
                        // AutoFill's "Request code" hand-off (no CloudKit entitlement there) —
                        // presented once unlocked (see VaultShellBehaviors).
                        env.pendingSharedItemDeepLinkID = itemID
                    }
                }
                // Universal Link: share-invite (invite.looxpassword.com/i/<token>#k=…).
                // Resolve + accept in background; the unlocked shell picks the
                // acceptance up via the standard breadcrumb/resume flow.
                // Invite links arrive via the scene delegate (a custom scene
                // delegate takes over NSUserActivity delivery from SwiftUI).
                .onReceive(NotificationCenter.default.publisher(for: .inviteLinkReceived)) { note in
                    guard let url = note.object as? URL else { return }
                    handleInviteLink(url)
                }
                // Cold launch: the scene delegate buffered the link before
                // this view (and its onReceive) existed — drain it now.
                .task {
                    if let url = PendingInviteLink.url { handleInviteLink(url) }
                    AnalyticsEngine.shared.refreshUserProperties(
                        tier: env.entitlements.tier,
                        language: env.settings.preferredLanguage,
                        iCloudSyncEnabled: env.settings.iCloudSyncEnabled)
                }
                // A dead/expired invite link must say so — silence here reads
                // as "the app is broken" and gets blamed on the sender.
                .alert("Couldn't accept the invitation",
                       isPresented: Binding(get: { inviteError != nil },
                                            set: { if !$0 { inviteError = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(verbatim: inviteError ?? "")
                }
                .alert("Invitation accepted", isPresented: $inviteAccepted) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Unlock your vault and open \"Shared with Me\" on Home to finish setting up.")
                }
                // One shared environment chain (see `VaultRootEnvironment`) — the
                // same modifier every UIKit-pushed hosting controller re-applies,
                // so the root window and pushed detail screens can never drift.
                .modifier(VaultRootEnvironment(env: env))
    }
}
