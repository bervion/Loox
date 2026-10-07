import SwiftUI
import AuthenticationServices

/// Navigation value that pushes Settings onto the Home stack (Apple-Settings
/// idiom: a pushed screen with a back button, not a modal sheet).
struct SettingsRoute: Hashable, Codable {}

/// Settings — pushed from Home. A large left-aligned title that collapses into
/// the nav bar on scroll, and Apple-Settings-style root cards: no section
/// headers (the badge + name carries the meaning), everyday and security prefs
/// gathered into child screens.
struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmErase = false
    @State private var showAutoFillGuide = false
    @State private var showTutorialsReset = false
    @State private var confirmApprovalModeOff = false
    @State private var revokingLeftoverLinks = false
    @State private var leftoverLinksStillLive = false

    /// One Online Features row: preference toggle + operator/runtime status
    /// (dot + label, the iCloud+ idiom). The toggle mutates ONLY the user
    /// preference (INV-CAP-09).
    private func onlineFeatureRow(_ id: CapabilityID, title: LocalizedStringKey,
                                  badge: SettingsIconBadge) -> some View {
        Toggle(isOn: Binding(
            get: { env.capabilities.userPreference(id) },
            set: { env.capabilities.setUserPreference(id, enabled: $0) })) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    HStack(spacing: Space.s1) {
                        CapabilityStatusDot(status: .resolve(id, store: env.capabilities), size: 6)
                        Text(verbatim: CapabilityStatusText.label(
                            env.capabilities.availability(id, operation: .create)))
                            .vaultType(.caption).themedForeground(.secondary)
                    }
                }
            } icon: { badge }
        }
        .tint(Color(rgb: env.theme.active.switchOn))
    }

    /// The erase itself lives in `AppEnvironment.erase` so this screen and the
    /// macOS Settings window run the identical fail-closed sequence. The view
    /// only presents the outcome and the three ways out of a blocked erase.
    private var eraseBlocked: Binding<Bool> {
        Binding(get: { env.erase.isBlocked },
                set: { if !$0 { env.erase.cancel() } })
    }

    /// Quick links that survived a previous erase because their revoke call
    /// never landed. The per-item Quick Links sheet cannot reach them (their
    /// item is gone), so this is the only remaining way to kill them.
    private var leftoverLinks: [LooxLinkRecord] {
        let itemIDs = Set(env.repository.items.map(\.id))
        return env.looxLinks.records.records.filter { !$0.isExpired && !itemIDs.contains($0.itemId) }
    }

    private func revokeLeftoverLinks() async {
        revokingLeftoverLinks = true
        defer { revokingLeftoverLinks = false }
        var stillLive = false
        for record in leftoverLinks {
            do { try await env.looxLinks.revoke(record) } catch { stillLive = true }
        }
        leftoverLinksStillLive = stillLive
    }

    /// Approval Mode (ADR-2): deliberately independent of `iCloudSyncEnabled` — turning
    /// this on/off must never touch vault-item sync. Turning OFF only pauses the approval
    /// listening services — it does not revoke or delete any existing CKShare, so a
    /// confirmation states that plainly instead of silently flipping.
    private var approvalModeBinding: Binding<Bool> {
        Binding(
            get: { env.settings.approvalModeEnabled },
            set: { isOn in
                if isOn {
                    env.settings.approvalModeEnabled = true
                    Haptics.tap()
                } else {
                    confirmApprovalModeOff = true
                }
            })
    }

    /// Ask iOS to turn Loox on as the AutoFill (password / passkey) provider.
    ///
    /// The iOS 18+ in-app prompt only ever APPEARS while the provider is off,
    /// and the system suppresses it after earlier refusals — in both cases the
    /// call returns immediately with no UI, which read as a dead row. The tap
    /// must always land somewhere: already-enabled or suppressed-prompt paths
    /// deep-link to the provider settings instead.
    private func setUpPasswordAutoFill() {
        Task {
            let state = await ASCredentialIdentityStore.shared.state()
            if state.isEnabled {
                try? await ASSettingsHelper.openCredentialProviderAppSettings()
                return
            }
            if #available(iOS 18.0, *) {
                let start = ContinuousClock.now
                let turnedOn = await ASSettingsHelper.requestToTurnOnCredentialProviderExtension()
                // An instant `false` means no sheet was shown (prompt quota
                // exhausted) — fall back to Settings. A slow `false` means the
                // user saw the sheet and declined; don't nag them twice.
                if !turnedOn, ContinuousClock.now - start < .milliseconds(700) {
                    try? await ASSettingsHelper.openCredentialProviderAppSettings()
                }
            } else {
                try? await ASSettingsHelper.openCredentialProviderAppSettings()
            }
        }
    }

    /// Deep-link straight to the Verification Codes (one-time code) provider settings.
    private func setUpVerificationCodes() {
        Task { try? await ASSettingsHelper.openVerificationCodeAppSettings() }
    }

    var body: some View {
        let switchTint = Color(rgb: env.theme.active.switchOn)
        Form {
            // Everyday preferences + security, gathered into child screens.
            Section {
                NavigationLink { GeneralSettingsView() } label: {
                    Label { Text("General") } icon: { SettingsIconBadge(systemName: "gear", tint: SettingsBadgeTint.gray) }
                }
                NavigationLink { SecuritySettingsView() } label: {
                    Label { Text("Security") } icon: { SettingsIconBadge(systemName: "lock.fill", tint: SettingsBadgeTint.blue) }
                }
                NavigationLink { AppearanceSettingsView() } label: {
                    Label { Text("Appearance") } icon: { SettingsIconBadge(systemName: "paintbrush.fill", tint: SettingsBadgeTint.pink) }
                }
                NavigationLink { NotificationsSettingsView() } label: {
                    Label { Text("Notifications") } icon: { SettingsIconBadge(systemName: "bell.badge.fill", tint: SettingsBadgeTint.red) }
                }
            }
            .listRowBackground(VaultColors.surface)

            // AutoFill
            Section {
                // The guide runs first: iOS drops the user into Settings with
                // no idea which of several similarly named rows to look for,
                // which is where setup was abandoned. It ends by deep-linking.
                Button { showAutoFillGuide = true } label: {
                    Label { Text("Set up password AutoFill") } icon: { SettingsIconBadge(systemName: "keyboard.fill", tint: SettingsBadgeTint.blue) }
                }
                .tutorialAnchor(TutorialAnchorID.settingsAutoFill)
                Button(action: setUpVerificationCodes) {
                    Label { Text("Set up verification codes") } icon: { SettingsIconBadge(systemName: "123.rectangle.fill", tint: SettingsBadgeTint.teal) }
                }
            } footer: {
                Text("Use Loox to fill passwords and one-time codes in other apps and Safari.")
            }
            .listRowBackground(VaultColors.surface)

            // Vault data
            Section {
                NavigationLink { ManageFoldersScreen() } label: {
                    Label { Text("Spaces") } icon: { SettingsIconBadge(systemName: "folder.fill", tint: SettingsBadgeTint.orange) }
                }
                NavigationLink { SyncSettingsView() } label: {
                    Label { Text("iCloud Sync") } icon: { SettingsIconBadge(systemName: "icloud.fill", tint: SettingsBadgeTint.blue) }
                }
                NavigationLink { PasskeysScreen() } label: {
                    Label { Text("Passkeys") } icon: { SettingsIconBadge(systemName: "person.badge.key.fill", tint: SettingsBadgeTint.purple) }
                }
                NavigationLink { BackupSettingsView() } label: {
                    Label { Text("Backup") } icon: { SettingsIconBadge(systemName: "externaldrive.fill", tint: SettingsBadgeTint.teal) }
                }
            }
            .listRowBackground(VaultColors.surface)

            // Sharing + optional network capabilities: user preference (the
            // toggles) and operator availability are independent axes — an
            // outage shows in the status text but NEVER flips a toggle.
            Section {
                Toggle(isOn: approvalModeBinding) {
                    Label { Text("Approval Mode") } icon: { SettingsIconBadge(systemName: "person.2.fill", tint: SettingsBadgeTint.green) }
                }
                .tint(switchTint)
                onlineFeatureRow(.privateEmail, title: "Private Email",
                                 badge: SettingsIconBadge(systemName: "envelope.fill", tint: SettingsBadgeTint.teal))
                onlineFeatureRow(.shareLink, title: "Share Links",
                                 badge: SettingsIconBadge(systemName: "link", tint: SettingsBadgeTint.green))
            } footer: {
                Text("Share a login with someone and approve each request before they can use it, over iCloud. Independent of iCloud Sync above.")
            }
            .listRowBackground(VaultColors.surface)

            Section {
                // Deliberate lock: the lock screen requires a slide before Face ID,
                // otherwise the camera re-opens the vault the instant it locks.
                Button { env.session.lock(deliberate: true) } label: {
                    Label { Text("Lock Now") } icon: { SettingsIconBadge(systemName: "lock.fill", tint: SettingsBadgeTint.gray) }
                }
                .accessibilityIdentifier("settings.lock-now")
                Button(role: .destructive) { confirmErase = true } label: {
                    HStack {
                        Label { Text("Erase Vault").foregroundStyle(env.theme.active.color(.destructive)) }
                            icon: { SettingsIconBadge(systemName: "trash.fill", tint: SettingsBadgeTint.red) }
                        if env.erase.isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .accessibilityIdentifier("settings.erase-vault")
                .disabled(env.erase.isWorking)
                if !leftoverLinks.isEmpty {
                    Button { Task { await revokeLeftoverLinks() } } label: {
                        HStack {
                            Label { Text("Turn off leftover links") }
                                icon: { SettingsIconBadge(systemName: "link", tint: SettingsBadgeTint.orange) }
                            if revokingLeftoverLinks {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(revokingLeftoverLinks)
                }
            } footer: {
                if !leftoverLinks.isEmpty {
                    Text("Links shared before an earlier erase are still readable until they expire. Turning them off needs a connection.")
                }
            }
            .listRowBackground(VaultColors.surface)

            #if DEBUG
            Section {
                NavigationLink { RelayDiagnosticsView() } label: {
                    Label { Text("Private Email diagnostics") }
                        icon: { SettingsIconBadge(icon: Icons.mail, tint: SettingsBadgeTint.gray) }
                }
                NavigationLink { ShareDiagnosticsView() } label: {
                    Label { Text(verbatim: "Share Diagnostics") } icon: { SettingsIconBadge(systemName: "ladybug.fill", tint: SettingsBadgeTint.gray) }
                }
                // Dev-only purchase surfaces (paywall, plan section, gate
                // sheets) — Release beta builds get these automatically via
                // AppTransaction; DEBUG opts in here (paywall preview works
                // best under the Vaultify-StoreKit scheme).
                Toggle(isOn: Binding(
                    get: { env.entitlements.debugPurchasesEnabled },
                    set: { env.entitlements.debugPurchasesEnabled = $0 }
                )) {
                    Label { Text(verbatim: "Purchase Surfaces") } icon: { SettingsIconBadge(systemName: "cart.fill", tint: SettingsBadgeTint.gray) }
                }
                .tint(switchTint)
                // Dev-only tier override (`LooxTier(rawValue: -1)` is nil = follow
                // StoreKit) so membership UI is testable without ASC products.
                Picker(selection: Binding(
                    get: { env.entitlements.debugTierOverride?.rawValue ?? -1 },
                    set: { env.entitlements.debugTierOverride = LooxTier(rawValue: $0) }
                )) {
                    Text(verbatim: "StoreKit").tag(-1)
                    Text(verbatim: "Free").tag(LooxTier.free.rawValue)
                    Text(verbatim: "Loox+").tag(LooxTier.plus.rawValue)
                    Text(verbatim: "Loox Max").tag(LooxTier.max.rawValue)
                } label: {
                    Label { Text(verbatim: "Loox Tier Override") } icon: { SettingsIconBadge(systemName: "crown.fill", tint: SettingsBadgeTint.gray) }
                }
            }
            .listRowBackground(VaultColors.surface)
            #endif

            Section {
                // Someone who skipped the tours on day one, or who inherited a
                // vault another person set up, has no other route back to them.
                Button {
                    env.tutorial.replayAll()
                    showTutorialsReset = true
                } label: {
                    Label { Text("Show tutorials again") } icon: { SettingsIconBadge(systemName: "questionmark.circle.fill", tint: SettingsBadgeTint.teal) }
                }
                NavigationLink { AboutView() } label: {
                    Label { Text("About") } icon: { SettingsIconBadge(systemName: "info", tint: SettingsBadgeTint.gray) }
                }
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        // Native iOS switch metrics (the app root applies a custom .themed style;
        // override it here). Colours come from each toggle's explicit .tint.
        .toggleStyle(.switch)
        .navigationTitle("Settings")
        .platformNavigationBarTitleDisplayMode(.large)
        .analyticsScreen("settings")
        // Screen-open health probe so the Online Features status rows reflect
        // live service state, not the last cached verdict. Contextual and
        // non-blocking (INV-CAP-02); the breaker inside `probe` rate-limits.
        // Sequential on purpose — the store is MainActor state.
        .task {
            for id in [CapabilityID.privateEmail, .shareLink]
            where env.capabilities.userPreference(id) {
                await CapabilityHealthProbe.probe(id, store: env.capabilities)
            }
        }
        .alert(Text("Tutorials reset"), isPresented: $showTutorialsReset) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The guided tours will play again the next time you open those screens.")
        }
        .sheet(isPresented: $showAutoFillGuide) {
            NavigationStack { AutoFillSetupGuide(openSettings: setUpPasswordAutoFill) }
        }
        // One blocked-erase surface for every remote step, not just aliases:
        // an unreachable service must never make an erase impossible, and it
        // must never silently pretend the remote copy is gone either.
        .alert(Text("Some things are still live"), isPresented: eraseBlocked) {
            Button("Try Again") { Task { await env.erase.retry() } }
            Button("Erase Anyway", role: .destructive) { env.erase.eraseAnyway() }
            Button("Cancel", role: .cancel) { env.erase.cancel() }
        } message: {
            Text(verbatim: env.erase.report.failureMessage)
        }
        .alert(Text("Some links are still live"), isPresented: $leftoverLinksStillLive) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again. Loox still has what it needs to turn them off.")
        }
        .confirmationDialog("Erase the entire vault?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase Everywhere", role: .destructive) { Task { await env.erase.begin(.everywhere) } }
            Button("Erase on This Device", role: .destructive) { Task { await env.erase.begin(.thisDevice) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Erase everywhere also turns off your quick links and private email aliases, stops shared logins, and deletes the iCloud copy. Erase on this device removes Loox data from this device only and leaves all of that running.")
        }
        .confirmationDialog("Turn off Approval Mode?", isPresented: $confirmApprovalModeOff, titleVisibility: .visible) {
            Button("Turn Off", role: .destructive) {
                env.settings.approvalModeEnabled = false
                Haptics.tap()
            }
        } message: {
            Text("Logins you already shared stay shared. New approval requests and invites pause until you turn this back on.")
        }
    }
}
