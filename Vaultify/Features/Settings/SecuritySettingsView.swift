import SwiftUI

/// "Security" — every lock / protection / credential-hygiene control gathered off
/// the Settings root into one child screen (Apple-Settings idiom).
struct SecuritySettingsView: View {
    @Environment(AppEnvironment.self) private var env

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

    var body: some View {
        @Bindable var settings = env.settings
        let switchTint = Color(rgb: env.theme.active.switchOn)
        Form {
            Section {
                if BiometricAuth.isAvailable {
                    Toggle(isOn: biometricBinding) {
                        Label { Text("Unlock with \(BiometricAuth.displayName)") } icon: { SettingsIconBadge(systemName: BiometricAuth.systemImage, tint: SettingsBadgeTint.green) }
                    }
                    .tint(switchTint)
                }
                NavigationLink {
                    SettingsSelectionScreen(
                        title: "Auto-Lock",
                        options: AutoLockTimeout.allCases.map { .init(value: $0, label: $0.title) },
                        selection: $settings.autoLock,
                        footer: "Auto-Lock counts both time away from the app and idle time in it. \"Immediately\" locks the moment you leave; longer windows let you copy something into another app and come back without re-authenticating.")
                } label: {
                    LabeledContent {
                        Text(settings.autoLock.title)
                    } label: {
                        Label { Text("Auto-Lock") } icon: { SettingsIconBadge(systemName: "lock.badge.clock", tint: SettingsBadgeTint.indigo) }
                    }
                }
                Toggle(isOn: $settings.shakeToLock) {
                    Label { Text("Shake to lock") } icon: { SettingsIconBadge(systemName: "iphone.radiowaves.left.and.right", tint: SettingsBadgeTint.orange) }
                }
                .tint(switchTint)
            }
            .listRowBackground(VaultColors.surface)

            Section {
                NavigationLink { ChangeMasterPasswordView() } label: {
                    Label { Text("Change Master Password") } icon: { SettingsIconBadge(systemName: "key.fill", tint: SettingsBadgeTint.blue) }
                }
                NavigationLink { RegenerateKitView() } label: {
                    Label { Text("Emergency Kit") } icon: { SettingsIconBadge(systemName: "cross.case.fill", tint: SettingsBadgeTint.red) }
                }
                NavigationLink { Level2SettingsView() } label: {
                    Label { Text("Extra Protection") } icon: { SettingsIconBadge(systemName: "lock.shield.fill", tint: SettingsBadgeTint.gray) }
                }
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Toggle(isOn: $settings.hibpEnabled) {
                    Label { Text("Check for known breaches") } icon: { SettingsIconBadge(systemName: "checkmark.shield.fill", tint: SettingsBadgeTint.green) }
                }
                .tint(switchTint)
                Toggle(isOn: automaticPasskeyBinding) {
                    Label { Text("Automatic passkey upgrades") } icon: { SettingsIconBadge(systemName: "person.badge.key.fill", tint: SettingsBadgeTint.purple) }
                }
                .tint(switchTint)
            } footer: {
                Text("Passkey upgrades can create passkeys in the background. Using them still requires unlocking your vault.")
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle("Security")
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}
