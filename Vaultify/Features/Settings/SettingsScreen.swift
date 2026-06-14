import SwiftUI

/// The Settings tab.
struct SettingsScreen: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmErase = false

    private var biometricBinding: Binding<Bool> {
        Binding(
            get: { env.settings.biometricUnlockEnabled },
            set: { isOn in
                if isOn { Task { try? await env.session.enableBiometricUnlock() } }
                else { env.session.disableBiometricUnlock() }
            })
    }

    var body: some View {
        @Bindable var settings = env.settings
        NavigationStack {
            Form {
                Section("Security") {
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
                    Toggle(isOn: $settings.lockOnBackground) {
                        Label { Text("Lock when backgrounded") } icon: { PolarisIcon(Icons.lock) }
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
                }
                .listRowBackground(VaultColors.surface)

                Section("Organization") {
                    NavigationLink { ManageFoldersScreen() } label: {
                        Label { Text("Spaces") } icon: { PolarisIcon(Icons.folder) }
                    }
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
                    NavigationLink { ImportView() } label: {
                        Label { Text("Import") } icon: { PolarisIcon(Icons.importData) }
                    }
                    NavigationLink { ExportView() } label: {
                        Label { Text("Export") } icon: { PolarisIcon(Icons.exportData) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    Button { env.session.lock() } label: {
                        Label { Text("Lock Now") } icon: { PolarisIcon(Icons.lockFill) }
                    }
                    Button(role: .destructive) { confirmErase = true } label: {
                        Label { Text("Erase Vault").foregroundStyle(.red) } icon: { PolarisIcon(Icons.delete).foregroundStyle(.red) }
                    }
                }
                .listRowBackground(VaultColors.surface)

                Section {
                    NavigationLink { AboutView() } label: {
                        Label { Text("About") } icon: { PolarisIcon(Icons.info) }
                    }
                }
                .listRowBackground(VaultColors.surface)
            }
            .themedFormBackground()
            .navigationTitle("Settings")
            .confirmationDialog("Erase the entire vault?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase Everything", role: .destructive) { env.eraseEverything() }
            } message: {
                Text("This permanently deletes every item and key on this device. This cannot be undone.")
            }
        }
    }
}
