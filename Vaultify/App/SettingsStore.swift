import SwiftUI

/// App appearance preference.
nonisolated enum AppearanceMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var title: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
        return base.inAppLocalized
    }
}

/// Inactivity timeout before the vault auto-locks.
nonisolated enum AutoLockTimeout: Int, CaseIterable, Codable, Sendable, Identifiable {
    case immediate = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3600
    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var title: LocalizedStringResource {
        let base: LocalizedStringResource = switch self {
        case .immediate: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        case .fifteenMinutes: "After 15 minutes"
        case .oneHour: "After 1 hour"
        }
        return base.inAppLocalized
    }
}

/// Non-sensitive preference flags persisted in `UserDefaults`. No secrets here.
@MainActor @Observable final class SettingsStore {
    @ObservationIgnored private let defaults = UserDefaults.standard

    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Key.onboarding) } }
    /// Single lock timer: `.immediate` locks the moment the app is hidden; any other
    /// window applies to BOTH backgrounding and foreground idle (the old separate
    /// "lock on background" toggle instant-locked regardless of this, which made a
    /// quick copy-into-another-app round trip re-prompt every time).
    var autoLock: AutoLockTimeout { didSet { defaults.set(autoLock.rawValue, forKey: Key.autoLock) } }
    /// Lock the vault on a deliberate device shake (privacy panic gesture). Opt-in.
    var shakeToLock: Bool { didSet { defaults.set(shakeToLock, forKey: Key.shakeToLock) } }
    var biometricUnlockEnabled: Bool { didSet { defaults.set(biometricUnlockEnabled, forKey: Key.biometric) } }
    /// Set once the biometric Vault Key has moved from the legacy per-app keychain group into the
    /// shared group (so the AutoFill extension can use Face ID). Guards the one-time migration.
    var biometricKeyMigratedToSharedGroup: Bool { didSet { defaults.set(biometricKeyMigratedToSharedGroup, forKey: Key.biometricKeyMigrated) } }
    var hibpEnabled: Bool { didSet { defaults.set(hibpEnabled, forKey: Key.hibp) } }
    var iCloudSyncEnabled: Bool { didSet { defaults.set(iCloudSyncEnabled, forKey: Key.icloud) } }
    /// Approval Mode transport (CKShare grants/requests/responses). Deliberately
    /// SEPARATE from `iCloudSyncEnabled`: enabling approval sharing must never
    /// imply vault-item uploads, and the approval push pipeline must never be
    /// gated by the vault-sync toggle (control plane ≠ secret plane).
    var approvalModeEnabled: Bool { didSet { defaults.set(approvalModeEnabled, forKey: Key.approvalMode) } }
    var showWebsiteIcons: Bool { didSet { defaults.set(showWebsiteIcons, forKey: Key.favicons) } }
    var clipboardClearSeconds: Int { didSet { defaults.set(clipboardClearSeconds, forKey: Key.clipboard) } }
    var hideInAppSwitcher: Bool { didSet { defaults.set(hideInAppSwitcher, forKey: Key.privacyScreen) } }
    /// Which payment card the Profile screen shows as "your" card. Device-local (not synced) —
    /// a display preference, unlike the synced default identity. nil = fall back to the first card.
    var selectedPaymentCardId: String? { didSet { defaults.set(selectedPaymentCardId, forKey: Key.selectedCard) } }
    var preferredLanguage: String {
        didSet {
            defaults.set(preferredLanguage, forKey: Key.language)
            // Mirror into the App Group so the AutoFill extension localizes against the same choice.
            SharedConfig.sharedDefaults.set(preferredLanguage, forKey: SharedConfig.languageKey)
            appResourceLocale = appLocale(forCode: preferredLanguage)
        }
    }

    init() {
        let d = UserDefaults.standard
        onboardingCompleted = d.bool(forKey: Key.onboarding)
        autoLock = AutoLockTimeout(rawValue: d.object(forKey: Key.autoLock) as? Int ?? 300) ?? .fiveMinutes
        shakeToLock = d.object(forKey: Key.shakeToLock) as? Bool ?? false
        biometricUnlockEnabled = d.bool(forKey: Key.biometric)
        biometricKeyMigratedToSharedGroup = d.bool(forKey: Key.biometricKeyMigrated)
        hibpEnabled = d.object(forKey: Key.hibp) as? Bool ?? true
        iCloudSyncEnabled = d.bool(forKey: Key.icloud)
        approvalModeEnabled = d.bool(forKey: Key.approvalMode)
        showWebsiteIcons = d.object(forKey: Key.favicons) as? Bool ?? true
        clipboardClearSeconds = d.object(forKey: Key.clipboard) as? Int ?? 30
        hideInAppSwitcher = d.object(forKey: Key.privacyScreen) as? Bool ?? true
        selectedPaymentCardId = d.string(forKey: Key.selectedCard)
        preferredLanguage = d.string(forKey: Key.language) ?? "system"
        SharedConfig.sharedDefaults.set(preferredLanguage, forKey: SharedConfig.languageKey)
        appResourceLocale = appLocale(forCode: preferredLanguage)
    }

    private enum Key {
        static let onboarding = "onboarding_completed"
        static let autoLock = "auto_lock_timeout"
        static let shakeToLock = "shake_to_lock"
        static let biometric = "biometric_unlock_enabled"
        static let biometricKeyMigrated = "biometric_key_migrated_shared_group"
        static let hibp = "hibp_enabled"
        static let icloud = "icloud_sync_enabled"
        static let approvalMode = "approval_mode_enabled"
        static let favicons = "show_website_icons"
        static let clipboard = "clipboard_clear_seconds"
        static let privacyScreen = "hide_in_app_switcher"
        static let selectedCard = "profile_selected_payment_card_id"
        static let language = "preferred_language"
    }
}
