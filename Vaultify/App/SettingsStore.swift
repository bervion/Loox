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
    var autoLock: AutoLockTimeout {
        didSet {
            defaults.set(autoLock.rawValue, forKey: Key.autoLock)
            mirrorAutoLock()
        }
    }
    /// Lock the vault on a deliberate device shake (privacy panic gesture). Opt-in.
    var shakeToLock: Bool { didSet { defaults.set(shakeToLock, forKey: Key.shakeToLock) } }
    var biometricUnlockEnabled: Bool { didSet { defaults.set(biometricUnlockEnabled, forKey: Key.biometric) } }
    /// Set once the biometric Vault Key has moved from the legacy per-app keychain group into the
    /// shared group (so the AutoFill extension can use Face ID). Guards the one-time migration.
    var biometricKeyMigratedToSharedGroup: Bool { didSet { defaults.set(biometricKeyMigratedToSharedGroup, forKey: Key.biometricKeyMigrated) } }
    var hibpEnabled: Bool { didSet { defaults.set(hibpEnabled, forKey: Key.hibp) } }
    /// Master switch for rotation-reminder local notifications. Default ON so existing
    /// behavior is preserved for users who never touch this new setting. Gated at the
    /// `RotationNotificationService.schedule` call sites via `isRotationRemindersEnabled()`
    /// below rather than inside the service itself (kept untouched, no restructure).
    var rotationRemindersEnabled: Bool { didSet { defaults.set(rotationRemindersEnabled, forKey: Key.rotationReminders) } }
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
    /// Last Home Space filter, remembered per identity so it survives relaunch.
    /// Device-local display preference — deliberately NOT synced (a selected-Space
    /// choice reveals nothing sensitive and needn't cross devices). Keyed by
    /// identity id; today everything uses `PersonaID.placeholder`. Value is a
    /// folderId, or "" for an explicit "All Spaces" choice; absence of a key
    /// means the user never chose (Home's single-Space auto-select may fill it).
    private(set) var lastSelectedSpaceByPersona: [String: String] {
        didSet { defaults.set(lastSelectedSpaceByPersona, forKey: Key.lastSelectedSpaces) }
    }

    /// Which persona the UI currently acts as. Device-local selection (not synced,
    /// unlike the persona's converged `isDefault` flag): the active view is a
    /// per-device UI concern, and a persona id reveals nothing without the sealed
    /// name. nil / stale falls back to the default persona.
    var activePersonaID: String? { didSet { defaults.set(activePersonaID, forKey: Key.activePersona) } }

    /// The remembered Home Space for an identity: a folderId, "" for an explicit
    /// "All Spaces" choice, or nil when the user never chose one.
    func lastSelectedSpace(persona: String) -> String? {
        lastSelectedSpaceByPersona[persona]
    }

    /// Remember the Home Space for an identity. nil records the EXPLICIT
    /// "All Spaces" choice (stored as "") — it must survive tab switches and
    /// relaunches rather than being erased and re-auto-selected away.
    func setLastSelectedSpace(_ folderId: String?, persona: String) {
        lastSelectedSpaceByPersona[persona] = folderId ?? ""
    }

    /// Forget an identity's remembered Space entirely (back to "never chose") —
    /// for cleanup when a persona is removed, and for tests.
    func clearLastSelectedSpace(persona: String) {
        lastSelectedSpaceByPersona.removeValue(forKey: persona)
    }
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
        rotationRemindersEnabled = d.object(forKey: Key.rotationReminders) as? Bool ?? true
        iCloudSyncEnabled = d.bool(forKey: Key.icloud)
        approvalModeEnabled = d.bool(forKey: Key.approvalMode)
        showWebsiteIcons = d.object(forKey: Key.favicons) as? Bool ?? true
        clipboardClearSeconds = d.object(forKey: Key.clipboard) as? Int ?? 30
        hideInAppSwitcher = d.object(forKey: Key.privacyScreen) as? Bool ?? true
        selectedPaymentCardId = d.string(forKey: Key.selectedCard)
        lastSelectedSpaceByPersona = d.dictionary(forKey: Key.lastSelectedSpaces) as? [String: String] ?? [:]
        activePersonaID = d.string(forKey: Key.activePersona)
        preferredLanguage = d.string(forKey: Key.language) ?? "system"
        SharedConfig.sharedDefaults.set(preferredLanguage, forKey: SharedConfig.languageKey)
        appResourceLocale = appLocale(forCode: preferredLanguage)
        mirrorAutoLock()
    }

    /// Mirror the auto-lock window into the App Group so the Safari web extension
    /// can size its unlocked session to the same policy (`UserDefaults.standard`
    /// stays the app's source of truth). Tightening to "immediate" also revokes
    /// any live extension session — the stricter policy applies at once.
    private func mirrorAutoLock() {
        SharedConfig.sharedDefaults.set(autoLock.rawValue, forKey: SharedConfig.autoLockSecondsKey)
        if autoLock == .immediate {
            ExtensionSessionStore.clear()
        }
    }

    /// Cheap, dependency-free read of the rotation-reminders preference for call sites
    /// that don't otherwise hold a `SettingsStore` instance (e.g. `VaultRepository`,
    /// which schedules rotation notifications on item save/update).
    nonisolated static func isRotationRemindersEnabled() -> Bool {
        UserDefaults.standard.object(forKey: Key.rotationReminders) as? Bool ?? true
    }

    private nonisolated enum Key {
        static let onboarding = "onboarding_completed"
        static let autoLock = "auto_lock_timeout"
        static let shakeToLock = "shake_to_lock"
        static let biometric = "biometric_unlock_enabled"
        static let biometricKeyMigrated = "biometric_key_migrated_shared_group"
        static let hibp = "hibp_enabled"
        static let rotationReminders = "rotation_reminders_enabled"
        static let icloud = "icloud_sync_enabled"
        static let approvalMode = "approval_mode_enabled"
        static let favicons = "show_website_icons"
        static let clipboard = "clipboard_clear_seconds"
        static let privacyScreen = "hide_in_app_switcher"
        static let selectedCard = "profile_selected_payment_card_id"
        static let lastSelectedSpaces = "last_selected_space_by_persona"
        static let activePersona = "active_persona_id"
        static let language = "preferred_language"
    }
}
