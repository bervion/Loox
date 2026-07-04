#if os(macOS)
import SwiftUI

/// Native macOS Settings window (App menu → Settings…, ⌘,): a sidebar of
/// categories with detail panes — the System Settings idiom — reusing the same
/// setting views the iOS sheet presents. Registered as a `Settings` scene in
/// `VaultifyApp`, so the menu item and shortcut come from the system.
struct MacSettingsView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case general, security, appearance, spaces, sync, passkeys, importData, exportData, about
        var id: String { rawValue }

        var label: LocalizedStringResource {
            switch self {
            case .general: return "General"
            case .security: return "Security"
            case .appearance: return "Appearance"
            case .spaces: return "Spaces"
            case .sync: return "iCloud Sync"
            case .passkeys: return "Passkeys"
            case .importData: return "Import"
            case .exportData: return "Export"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .general: return Icons.settings
            case .security: return Icons.lockFill
            case .appearance: return "ic_apps_filled"
            case .spaces: return Icons.folder
            case .sync: return Icons.sync
            case .passkeys: return Icons.passkey
            case .importData: return Icons.importData
            case .exportData: return Icons.exportData
            case .about: return Icons.info
            }
        }
    }

    @Environment(AppEnvironment.self) private var env
    @State private var pane: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                ForEach(Pane.allCases) { pane in
                    Label { Text(pane.label.inAppLocalized) } icon: { PolarisIcon(pane.icon) }
                        .tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            // Most panes read or mutate vault state — while locked, ask for an unlock
            // instead of exposing half-working screens.
            if env.session.state == .unlocked {
                detail(for: pane ?? .general)
            } else {
                lockedPlaceholder
            }
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 520, idealHeight: 600)
        .themedColorScheme()
        .tint(env.theme.uiTint)
    }

    /// Each pane hosts its own stack so drill-ins (Change Master Password,
    /// Auto-Night…) push within the detail column, like System Settings.
    @ViewBuilder private func detail(for pane: Pane) -> some View {
        switch pane {
        case .general: NavigationStack { MacGeneralSettingsPane() }
        case .security: NavigationStack { MacSecuritySettingsPane() }
        case .appearance: NavigationStack { AppearanceSettingsView() }
        case .spaces: NavigationStack { ManageFoldersScreen() }
        case .sync: NavigationStack { SyncSettingsView() }
        case .passkeys: NavigationStack { PasskeysScreen() }
        case .importData: NavigationStack { ImportView() }
        case .exportData: NavigationStack { ExportView() }
        case .about: NavigationStack { AboutView() }
        }
    }

    private var lockedPlaceholder: some View {
        VStack(spacing: Space.s4) {
            PolarisIcon(Icons.lockFill, size: 48).themedForeground(.secondary)
            Text("Unlock Loox in the main window to change settings.")
                .vaultType(.subhead).themedForeground(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - General

/// Language, icons, Watchtower, clipboard, and the lock/erase actions — the
/// grab-bag pane every settings window needs.
private struct MacGeneralSettingsPane: View {
    @Environment(AppEnvironment.self) private var env
    @State private var confirmErase = false

    var body: some View {
        @Bindable var settings = env.settings
        Form {
            Section("Appearance") {
                Picker(selection: $settings.preferredLanguage) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("Tiếng Việt").tag("vi")
                } label: {
                    Label { Text("Language") } icon: { PolarisIcon(Icons.language) }
                }
            }

            Section {
                Toggle(isOn: $settings.showWebsiteIcons) {
                    Label { Text("Show website icons") } icon: { PolarisIcon(Icons.globe) }
                }
                Toggle(isOn: $settings.hibpEnabled) {
                    Label { Text("Check for known breaches") } icon: { PolarisIcon(Icons.shield) }
                }
            } footer: {
                Text("Uses Google to fetch site icons as login avatars. This reveals the sites you have logins for to Google; turn off to keep everything on-device.")
            }

            Section("Privacy") {
                Picker(selection: $settings.clipboardClearSeconds) {
                    Text("After 15s").tag(15)
                    Text("After 30s").tag(30)
                    Text("After 1 min").tag(60)
                    Text("Never").tag(0)
                } label: {
                    Label { Text("Clear clipboard") } icon: { PolarisIcon(Icons.copy) }
                }
            }

            Section {
                Button { env.session.lock() } label: {
                    Label { Text("Lock Now") } icon: { PolarisIcon(Icons.lockFill) }
                }
                Button(role: .destructive) { confirmErase = true } label: {
                    Label { Text("Erase Vault").foregroundStyle(env.theme.active.color(.destructive)) }
                        icon: { PolarisIcon(Icons.delete).foregroundStyle(env.theme.active.color(.destructive)) }
                }
            }
        }
        .themedFormBackground()
        .navigationTitle("General")
        .confirmationDialog("Erase the entire vault?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive) { env.eraseEverything() }
        } message: {
            Text("This permanently deletes every item and key on this device. This cannot be undone.")
        }
    }
}

// MARK: - Security

/// Touch ID, auto-lock, and the key-management drill-ins. Mirrors the iOS
/// security section minus iOS-only rows (shake-to-lock, app-switcher shield).
private struct MacSecuritySettingsPane: View {
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
                Toggle(isOn: $settings.lockOnBackground) {
                    Label { Text("Lock when backgrounded") } icon: { PolarisIcon(Icons.lock) }
                }
            }

            Section {
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

            Section {
                Toggle(isOn: automaticPasskeyBinding) {
                    Label { Text("Automatic passkey upgrades") } icon: { PolarisIcon(Icons.passkey) }
                }
            } footer: {
                Text("Automatic passkey upgrades can create passkeys in the background with a write-only public key. Reading or using passkeys still requires unlocking your vault.")
            }
        }
        .themedFormBackground()
        .navigationTitle("Security")
    }
}
#endif
