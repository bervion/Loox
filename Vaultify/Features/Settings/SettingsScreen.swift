import SwiftUI
import AuthenticationServices

/// The Settings tab.
struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var confirmErase = false
    @State private var erasing = false
    @State private var relayBlockErase = false

    /// Erase, but tear down live relay aliases first. If the vault has active
    /// aliases and the relay can't be reached, the erase is BLOCKED (an "erase"
    /// must never leave anonymous addresses forwarding to a real inbox forever).
    /// With no active aliases (the common case) this awaits nothing meaningful.
    /// One Online Features row: preference toggle + operator/runtime status.
    /// The toggle mutates ONLY the user preference (INV-CAP-09).
    private func onlineFeatureRow(_ id: CapabilityID, title: LocalizedStringKey,
                                  icon: String) -> some View {
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
            } icon: { PolarisIcon(icon) }
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
                            Label { Text("Unlock with \(BiometricAuth.displayName)") } icon: { PolarisIcon(BiometricAuth.iconAsset) }
                        }
                    }
                    Picker(selection: $settings.autoLock) {
                        ForEach(AutoLockTimeout.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Label { Text("Auto-Lock") } icon: { PolarisIcon(Icons.clock) }
                    }
                    Toggle(isOn: $settings.shakeToLock) {
                        Label { Text("Shake to lock") } icon: { PolarisIcon(Icons.alert) }
                    }
                    NavigationLink {
                        ChangeMasterPasswordView()
                    } label: {
                        Label { Text("Change Master Password") } icon: { PolarisIcon(Icons.key) }
                    }
                    NavigationLink {
                        RegenerateKitView()
                    } label: {
                        Label { Text("Emergency Kit") } icon: { PolarisIcon(Icons.shield) }
                    }
                    NavigationLink {
                        Level2SettingsView()
                    } label: {
                        Label { Text("Extra Protection") } icon: { PolarisIcon(Icons.lockFill) }
                    }
                    Toggle(isOn: automaticPasskeyBinding) {
                        Label { Text("Automatic passkey upgrades") } icon: { PolarisIcon(Icons.passkey) }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Auto-Lock counts both time away from the app and idle time in it. \"Immediately\" locks the moment you leave; longer windows let you copy something into another app and come back without re-authenticating.\n\nAutomatic passkey upgrades can create passkeys in the background with a write-only public key. Reading or using passkeys still requires unlocking your vault.")
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    Button(action: setUpPasswordAutoFill) {
                        Label { Text("Set up password AutoFill") } icon: { PolarisIcon(Icons.key) }
                    }
                    Button(action: setUpVerificationCodes) {
                        Label { Text("Set up verification codes") } icon: { PolarisIcon(Icons.clock) }
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
                        Label { Text("Spaces") } icon: { PolarisIcon(Icons.folder) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                // Optional network capabilities: user preference (this toggle)
                // and operator availability are independent axes — an outage
                // shows in the status text but NEVER flips the toggle.
                Section("Online Features") {
                    onlineFeatureRow(.privateEmail, title: "Private Email", icon: Icons.mail)
                    onlineFeatureRow(.shareLink, title: "Share Links", icon: Icons.share)
                }
                .listRowBackground(VaultColors.surface)

                Section("Privacy") {
                    Toggle(isOn: $settings.hideInAppSwitcher) {
                        Label { Text("Hide contents in App Switcher") } icon: { PolarisIcon(Icons.hide) }
                    }
                    Picker(selection: $settings.clipboardClearSeconds) {
                        Text("After 15s").tag(15)
                        Text("After 30s").tag(30)
                        Text("After 1 min").tag(60)
                        Text("Never").tag(0)
                    } label: {
                        Label { Text("Clear clipboard") } icon: { PolarisIcon(Icons.copy) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    Toggle(isOn: $settings.showWebsiteIcons) {
                        Label { Text("Show website icons") } icon: { PolarisIcon(Icons.globe) }
                    }
                } footer: {
                    Text("Uses Google to fetch site icons as login avatars. This reveals the sites you have logins for to Google; turn off to keep everything on-device.")
                }
                .listRowBackground(VaultColors.surface)

                Section("Appearance") {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label { Text("Theme & Wallpaper") } icon: { PolarisIcon("ic_apps_filled") }
                    }
                    Picker(selection: $settings.preferredLanguage) {
                        Text("System").tag("system")
                        Text("English").tag("en")
                        Text("Tiếng Việt").tag("vi")
                    } label: {
                        Label { Text("Language") } icon: { PolarisIcon(Icons.language) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section("Watchtower") {
                    Toggle(isOn: $settings.hibpEnabled) {
                        Label { Text("Check for known breaches") } icon: { PolarisIcon(Icons.shield) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section("Data") {
                    NavigationLink { SyncSettingsView() } label: {
                        Label { Text("iCloud Sync") } icon: { PolarisIcon(Icons.sync) }
                    }
                    NavigationLink { PasskeysScreen() } label: {
                        Label { Text("Passkeys") } icon: { PolarisIcon(Icons.passkey) }
                    }
                    NavigationLink { ImportView() } label: {
                        Label { Text("Import") } icon: { PolarisIcon(Icons.importData) }
                    }
                    NavigationLink { ExportView() } label: {
                        Label { Text("Export") } icon: { PolarisIcon(Icons.exportData) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    // Deliberate lock: the lock screen requires a slide before Face ID,
                    // otherwise the camera re-opens the vault the instant it locks.
                    Button { env.session.lock(deliberate: true) } label: {
                        Label { Text("Lock Now") } icon: { PolarisIcon(Icons.lockFill) }
                    }
                    Button(role: .destructive) { confirmErase = true } label: {
                        Label { Text("Erase Vault").foregroundStyle(env.theme.active.color(.destructive)) }
                            icon: { PolarisIcon(Icons.delete).foregroundStyle(env.theme.active.color(.destructive)) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                #if DEBUG
                Section("Debug") {
                    NavigationLink { ShareDiagnosticsView() } label: {
                        Label { Text(verbatim: "Share Diagnostics") } icon: { PolarisIcon(Icons.share) }
                    }
                }
                .listRowBackground(VaultColors.surface)
                #endif

                Section {
                    NavigationLink { AboutView() } label: {
                        Label { Text("About") } icon: { PolarisIcon(Icons.info) }
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
        }
    }
}
