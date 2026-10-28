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
    /// Resolved but NOT accepted. Tapping a link must never join a stranger's
    /// share by itself: an accepted share publishes this device's participant
    /// identity into someone else's zone and lands in AutoFill, so the
    /// recipient sees who is sharing and decides here.
    @State private var pendingInvite: InviteLinkService.ResolvedInvite?
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
            // Must follow the engine: that call owns `FirebaseApp.configure()`,
            // and the reporter attaches only once a Firebase app exists.
            CrashReporter.bootstrap()
        }
    }

    /// Fixed identifiers for the crash-key catalog — never a localized or
    /// user-visible string.
    private static func lockStateIdentifier(_ state: VaultSession.State) -> String {
        switch state {
        case .onboarding: return "onboarding"
        case .locked: return "locked"
        case .unlocked: return "unlocked"
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
    /// Resolution only — a dead or malformed link still fails closed, and a
    /// live one waits for the explicit confirmation below.
    private func handleInviteLink(_ url: URL) {
        // A prompt already on screen must not have its share swapped out from
        // under the name the user is reading. Re-buffer instead of clobbering;
        // the cold-launch drain picks it up.
        guard pendingInvite == nil else {
            PendingInviteLink.url = url
            return
        }
        guard !inviteInFlight else { return }
        inviteInFlight = true
        PendingInviteLink.url = nil
        Task {
            defer { inviteInFlight = false }
            do {
                pendingInvite = try await env.inviteLinks.resolveInvite(from: url)
            } catch {
                inviteError = error.localizedDescription
                // The category only: the caught error carries the share URL and
                // the sender's account context (see `CrashReportFault`).
                CrashReporter.shared.record(.inviteLinkResolveFailed)
            }
        }
    }

    /// The user said yes with the sender named in front of them.
    private func acceptPendingInvite(_ invite: InviteLinkService.ResolvedInvite) {
        guard !inviteInFlight else { return }
        inviteInFlight = true
        Task {
            defer { inviteInFlight = false }
            do {
                try await env.inviteLinks.acceptShare(url: invite.shareURL)
                inviteAccepted = true
            } catch {
                inviteError = error.localizedDescription
                CrashReporter.shared.record(.inviteLinkAcceptFailed)
            }
        }
    }

    private var invitePrompt: Binding<Bool> {
        Binding(get: { pendingInvite != nil },
                // Swipe/system dismissal counts as declining: nothing joined.
                set: { if !$0 { pendingInvite = nil } })
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
                    } else if LooxMembershipDeepLink.matches(url) {
                        // The Loox Membership In-App Event's deep link.
                        env.pendingMembershipDeepLink = true
                    }
                }
                // Universal Link: share-invite (invite.looxpassword.com/i/<token>#k=…).
                // Resolve in background, confirm with the user, then accept;
                // the unlocked shell picks the acceptance up via the standard
                // breadcrumb/resume flow.
                // Invite links arrive via the scene delegate (a custom scene
                // delegate takes over NSUserActivity delivery from SwiftUI).
                .onReceive(NotificationCenter.default.publisher(for: .inviteLinkReceived)) { note in
                    guard let url = note.object as? URL else { return }
                    handleInviteLink(url)
                }
                // Cold launch: the scene delegate buffered the link before
                // this view (and its onReceive) existed — drain it now.
                .task {
                    // An export writes a plaintext CSV or an encrypted backup to
                    // the temp directory and hands it to the share sheet, which
                    // reports no completion. Anything still there at launch is a
                    // leftover from a share that was cancelled, or from a process
                    // that died before its own cleanup ran.
                    ExportTempFiles.purge()
                    if let url = PendingInviteLink.url { handleInviteLink(url) }
                    env.refreshAnalyticsUserProperties()
                    CrashReporter.shared.set(.appLanguage(env.settings.preferredLanguage))
                    CrashReporter.shared.set(.iCloudSync(enabled: env.settings.iCloudSyncEnabled))
                }
                // Whether the vault was locked is the first thing a crash report
                // has to answer, so the key tracks the live state rather than
                // being sampled once at launch.
                .onChange(of: env.session.state, initial: true) { _, state in
                    CrashReporter.shared.set(.vaultLockState(Self.lockStateIdentifier(state)))
                    // Artifact hygiene rides the lock-state edge: unlock runs
                    // the reconcile sweep (orphan staged files, records without
                    // bytes), and every transition wipes plaintext temp
                    // exports — a decrypted preview must not outlive its vault.
                    if state == .unlocked {
                        env.artifactStore.reconcile()
                    }
                    env.artifactStore.cleanupTempExports()
                }
                // Nothing is joined until this is answered.
                .alert(InvitePrompt.title(sender: pendingInvite?.senderDisplayName),
                       isPresented: invitePrompt, presenting: pendingInvite) { invite in
                    Button("Not now", role: .cancel) { pendingInvite = nil }
                    Button("Accept") { acceptPendingInvite(invite) }
                } message: { invite in
                    InvitePrompt.message(sender: invite.senderDisplayName)
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
