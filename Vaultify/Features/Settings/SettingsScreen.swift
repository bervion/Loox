import SwiftUI
import AuthenticationServices

/// The Settings tab.
struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var confirmErase = false
    @State private var erasing = false
    @State private var relayBlockErase = false
    @State private var confirmApprovalModeOff = false

    /// Erase, but tear down live relay aliases first. If the vault has active
    /// aliases and the relay can't be reached, the erase is BLOCKED (an "erase"
    /// must never leave anonymous addresses forwarding to a real inbox forever).
    /// With no active aliases (the common case) this awaits nothing meaningful.
    /// One Online Features row: preference toggle + operator/runtime status.
    /// The toggle mutates ONLY the user preference (INV-CAP-09).
    private func onlineFeatureRow(_ id: CapabilityID, title: LocalizedStringKey,
                                  badge: SettingsIconBadge) -> some View {
        Toggle(isOn: Binding(
            get: { env.capabilities.userPreference(id) },
            set: { env.capabilities.setUserPreference(id, enabled: $0) })) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(verbatim: CapabilityStatusText.label(
                        env.capabilities.availability(id, operation: .create)))
                        .vaultType(.caption).themedForeground(.secondary)
                }
            } icon: { badge }
        }
    }

    private func eraseWithRelayTeardown() {
        guard env.repository.aliases.contains(where: { $0.status == .active }) else {
            env.eraseEverything(); return
        }
        erasing = true
        Task {
            defer { erasing = false }
            do { try await env.relay.disableAllForErase() }
            catch { relayBlockErase = true; return }   // offline / unreachable → block
            env.eraseEverything()
        }
    }

    private var biometricBinding: Binding<Bool> {
        Binding(
            get: { env.settings.biometricUnlockEnabled },
            set: { isOn in
                if isOn { Task { try? await env.session.enableBiometricUnlock() } }
                else { env.session.disableBiometricUnlock() }
            })
    }

    private var automaticPasskeyBinding: Binding<Bool> {
        Binding(
            get: { SharedConfig.automaticPasskeyUpgradesEnabled },
            set: { SharedConfig.automaticPasskeyUpgradesEnabled = $0 })
    }

    /// Approval Mode (ADR-2): deliberately independent of `iCloudSyncEnabled` — turning
    /// this on/off must never touch vault-item sync. Turning ON is immediate (arms
    /// listening; harmless with no shares yet). Turning OFF only pauses the approval
    /// listening services (`OwnerShareRefresher`, `ApprovalCoordinator`,
    /// `InviteInboxCoordinator`, `SharedZoneSubscriptionService` all early-return on this
    /// flag) — it does not revoke or delete any existing CKShare, so a confirmation
    /// states that plainly instead of silently flipping.
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

    /// Ask iOS to turn Loox on as the AutoFill (password / passkey) provider. On iOS 18+
    /// this shows the system turn-on prompt right in the app; earlier iOS deep-links to the
    /// Settings AutoFill screen — either way the user skips hunting through Settings by hand.
    private func setUpPasswordAutoFill() {
        Task {
            if #available(iOS 18.0, *) {
                _ = await ASSettingsHelper.requestToTurnOnCredentialProviderExtension()
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
        @Bindable var settings = env.settings
        VaultSheetScaffold(title: "Settings",
                           leading: { EmptyView() },
                           trailing: { SheetDismissButton("Done") }) {
            Form {
                Section {
                    if BiometricAuth.isAvailable {
                        Toggle(isOn: biometricBinding) {
                            Label { Text("Unlock with \(BiometricAuth.displayName)") } icon: { SettingsIconBadge(icon: BiometricAuth.iconAsset, tint: SettingsBadgeTint.green) }
                        }
                    }
                    Picker(selection: $settings.autoLock) {
                        ForEach(AutoLockTimeout.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label { Text("Auto-Lock") } icon: { SettingsIconBadge(icon: Icons.clock, tint: SettingsBadgeTint.indigo) }
                    }
                    Toggle(isOn: $settings.shakeToLock) {
                        Label { Text("Shake to lock") } icon: { SettingsIconBadge(icon: Icons.alert, tint: SettingsBadgeTint.orange) }
                    }
                    NavigationLink {
                        ChangeMasterPasswordView()
                    } label: {
                        Label { Text("Change Master Password") } icon: { SettingsIconBadge(icon: Icons.key, tint: SettingsBadgeTint.blue) }
                    }
                    NavigationLink {
                        RegenerateKitView()
                    } label: {
                        Label { Text("Emergency Kit") } icon: { SettingsIconBadge(icon: Icons.shield, tint: SettingsBadgeTint.red) }
                    }
                    NavigationLink {
                        Level2SettingsView()
                    } label: {
                        Label { Text("Extra Protection") } icon: { SettingsIconBadge(icon: Icons.lockFill, tint: SettingsBadgeTint.gray) }
                    }
                    Toggle(isOn: automaticPasskeyBinding) {
                        Label { Text("Automatic passkey upgrades") } icon: { SettingsIconBadge(icon: Icons.passkey, tint: SettingsBadgeTint.purple) }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Auto-Lock counts both time away from the app and idle time in it. \"Immediately\" locks the moment you leave; longer windows let you copy something into another app and come back without re-authenticating.\n\nAutomatic passkey upgrades can create passkeys in the background with a write-only public key. Reading or using passkeys still requires unlocking your vault.")
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    Button(action: setUpPasswordAutoFill) {
                        Label { Text("Set up password AutoFill") } icon: { SettingsIconBadge(icon: Icons.key, tint: SettingsBadgeTint.blue) }
                    }
                    Button(action: setUpVerificationCodes) {
                        Label { Text("Set up verification codes") } icon: { SettingsIconBadge(icon: Icons.clock, tint: SettingsBadgeTint.teal) }
                    }
                } header: {
                    Text("AutoFill")
                } footer: {
                    Text("Use Loox to fill passwords and one-time codes in other apps and Safari.")
                }
                .listRowBackground(VaultColors.surface)

                Section("Organization") {
                    // Personas + Email aliases now live in Profile (identities belong with
                    // the profile, not buried in Settings).
                    NavigationLink { ManageFoldersScreen() } label: {
                        Label { Text("Spaces") } icon: { SettingsIconBadge(icon: Icons.folder, tint: SettingsBadgeTint.orange) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                // Optional network capabilities: user preference (this toggle)
                // and operator availability are independent axes — an outage
                // shows in the status text but NEVER flips the toggle.
                Section("Online Features") {
                    // SF envelope: the Polaris mail glyph distorts at badge scale.
                    onlineFeatureRow(.privateEmail, title: "Private Email",
                                     badge: SettingsIconBadge(systemName: "envelope.fill", tint: SettingsBadgeTint.teal))
                    onlineFeatureRow(.shareLink, title: "Share Links",
                                     badge: SettingsIconBadge(icon: Icons.share, tint: SettingsBadgeTint.green))
                }
                .listRowBackground(VaultColors.surface)

                Section("Privacy") {
                    Toggle(isOn: $settings.hideInAppSwitcher) {
                        Label { Text("Hide contents in App Switcher") } icon: { SettingsIconBadge(icon: Icons.hide, tint: SettingsBadgeTint.indigo) }
                    }
                    Picker(selection: $settings.clipboardClearSeconds) {
                        Text("After 15s").tag(15)
                        Text("After 30s").tag(30)
                        Text("After 1 min").tag(60)
                        Text("Never").tag(0)
                    } label: {
                        Label { Text("Clear clipboard") } icon: { SettingsIconBadge(icon: Icons.copy, tint: SettingsBadgeTint.gray) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section("Notifications") {
                    NavigationLink { NotificationsSettingsView() } label: {
                        Label { Text("Notifications") } icon: { SettingsIconBadge(icon: Icons.notification, tint: SettingsBadgeTint.red) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    Toggle(isOn: $settings.showWebsiteIcons) {
                        Label { Text("Show website icons") } icon: { SettingsIconBadge(icon: Icons.globe, tint: SettingsBadgeTint.blue) }
                    }
                } footer: {
                    Text("Uses Google to fetch site icons as login avatars. This reveals the sites you have logins for to Google; turn off to keep everything on-device.")
                }
                .listRowBackground(VaultColors.surface)

                Section("Appearance") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label { Text("Theme & Wallpaper") } icon: { SettingsIconBadge(icon: "ic_apps_filled", tint: SettingsBadgeTint.pink) }
                    }
                    Picker(selection: $settings.preferredLanguage) {
                        Text("System").tag("system")
                        Text("English").tag("en")
                        Text("Tiếng Việt").tag("vi")
                    } label: {
                        Label { Text("Language") } icon: { SettingsIconBadge(icon: Icons.language, tint: SettingsBadgeTint.blue) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section("Watchtower") {
                    Toggle(isOn: $settings.hibpEnabled) {
                        Label { Text("Check for known breaches") } icon: { SettingsIconBadge(icon: Icons.shield, tint: SettingsBadgeTint.green) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section("Data") {
                    NavigationLink { SyncSettingsView() } label: {
                        Label { Text("iCloud Sync") } icon: { SettingsIconBadge(systemName: "icloud.fill", tint: SettingsBadgeTint.blue) }
                    }
                    NavigationLink { PasskeysScreen() } label: {
                        Label { Text("Passkeys") } icon: { SettingsIconBadge(icon: Icons.passkey, tint: SettingsBadgeTint.purple) }
                    }
                    NavigationLink { ImportView() } label: {
                        Label { Text("Import") } icon: { SettingsIconBadge(icon: Icons.importData, tint: SettingsBadgeTint.teal) }
                    }
                    NavigationLink { ExportView() } label: {
                        Label { Text("Export") } icon: { SettingsIconBadge(icon: Icons.exportData, tint: SettingsBadgeTint.orange) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    Toggle(isOn: approvalModeBinding) {
                        Label { Text("Approval Mode") } icon: { SettingsIconBadge(icon: Icons.share, tint: SettingsBadgeTint.green) }
                    }
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Share a login with someone and approve each request before they can use it, over iCloud. Independent of iCloud Sync above.")
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    // Deliberate lock: the lock screen requires a slide before Face ID,
                    // otherwise the camera re-opens the vault the instant it locks.
                    Button { env.session.lock(deliberate: true) } label: {
                        Label { Text("Lock Now") } icon: { SettingsIconBadge(icon: Icons.lockFill, tint: SettingsBadgeTint.gray) }
                    }
                    Button(role: .destructive) { confirmErase = true } label: {
                        Label { Text("Erase Vault").foregroundStyle(env.theme.active.color(.destructive)) }
                            icon: { SettingsIconBadge(icon: Icons.delete, tint: SettingsBadgeTint.red) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                #if DEBUG
                Section("Debug") {
                    NavigationLink { ShareDiagnosticsView() } label: {
                        Label { Text(verbatim: "Share Diagnostics") } icon: { SettingsIconBadge(icon: Icons.share, tint: SettingsBadgeTint.gray) }
                    }
                }
                .listRowBackground(VaultColors.surface)
                #endif

                Section {
                    NavigationLink { AboutView() } label: {
                        Label { Text("About") } icon: { SettingsIconBadge(icon: Icons.info, tint: SettingsBadgeTint.gray) }
                    }
                }
                .listRowBackground(VaultColors.surface)
            }
            .alert(Text("Network needed"), isPresented: $relayBlockErase) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Connect to the internet so your private-email aliases can be turned off before erasing.")
            }
            .confirmationDialog("Erase the entire vault?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase Everything", role: .destructive) { eraseWithRelayTeardown() }
            } message: {
                Text("This permanently deletes every item and key on this device. This cannot be undone.")
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
}
