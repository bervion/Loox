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
    @State private var erasing = false
    @State private var relayBlockErase = false
    @State private var confirmApprovalModeOff = false

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
        .tint(Color(rgb: env.theme.active.switchOn))
    }

    /// Erase, but tear down live relay aliases first. If the vault has active
    /// aliases and the relay can't be reached, the erase is BLOCKED (an "erase"
    /// must never leave anonymous addresses forwarding to a real inbox forever).
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

    /// Ask iOS to turn Loox on as the AutoFill (password / passkey) provider. On iOS 18+
    /// this shows the system turn-on prompt right in the app; earlier iOS deep-links to the
    /// Settings AutoFill screen.
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
                Button(action: setUpPasswordAutoFill) {
                    Label { Text("Set up password AutoFill") } icon: { SettingsIconBadge(systemName: "keyboard.fill", tint: SettingsBadgeTint.blue) }
                }
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
                    Label { Text("Erase Vault").foregroundStyle(env.theme.active.color(.destructive)) }
                        icon: { SettingsIconBadge(systemName: "trash.fill", tint: SettingsBadgeTint.red) }
                }
            }
            .listRowBackground(VaultColors.surface)

            #if DEBUG
            Section {
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
