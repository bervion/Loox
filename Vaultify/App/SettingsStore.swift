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
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    var autoLock: AutoLockTimeout { didSet { defaults.set(autoLock.rawValue, forKey: Key.autoLock) } }
    var lockOnBackground: Bool { didSet { defaults.set(lockOnBackground, forKey: Key.lockOnBackground) } }
    var biometricUnlockEnabled: Bool { didSet { defaults.set(biometricUnlockEnabled, forKey: Key.biometric) } }
    var hibpEnabled: Bool { didSet { defaults.set(hibpEnabled, forKey: Key.hibp) } }
    var iCloudSyncEnabled: Bool { didSet { defaults.set(iCloudSyncEnabled, forKey: Key.icloud) } }
    var showWebsiteIcons: Bool { didSet { defaults.set(showWebsiteIcons, forKey: Key.favicons) } }
    var clipboardClearSeconds: Int { didSet { defaults.set(clipboardClearSeconds, forKey: Key.clipboard) } }
    var hideInAppSwitcher: Bool { didSet { defaults.set(hideInAppSwitcher, forKey: Key.privacyScreen) } }
    var homeShowRecentlyUsed: Bool { didSet { defaults.set(homeShowRecentlyUsed, forKey: Key.homeRecentlyUsed) } }
    var homeShowRecentlyModified: Bool { didSet { defaults.set(homeShowRecentlyModified, forKey: Key.homeRecentlyModified) } }
    var preferredLanguage: String {
        didSet {
            defaults.set(preferredLanguage, forKey: Key.language)
            appResourceLocale = appLocale(forCode: preferredLanguage)
        }
    }

    init() {
        let d = UserDefaults.standard
        onboardingCompleted = d.bool(forKey: Key.onboarding)
        appearance = AppearanceMode(rawValue: d.string(forKey: Key.appearance) ?? "") ?? .system
        autoLock = AutoLockTimeout(rawValue: d.object(forKey: Key.autoLock) as? Int ?? 300) ?? .fiveMinutes
        lockOnBackground = d.object(forKey: Key.lockOnBackground) as? Bool ?? true
        biometricUnlockEnabled = d.bool(forKey: Key.biometric)
        hibpEnabled = d.object(forKey: Key.hibp) as? Bool ?? true
        iCloudSyncEnabled = d.bool(forKey: Key.icloud)
        showWebsiteIcons = d.object(forKey: Key.favicons) as? Bool ?? true
        clipboardClearSeconds = d.object(forKey: Key.clipboard) as? Int ?? 30
        hideInAppSwitcher = d.object(forKey: Key.privacyScreen) as? Bool ?? true
        homeShowRecentlyUsed = d.bool(forKey: Key.homeRecentlyUsed)
        homeShowRecentlyModified = d.bool(forKey: Key.homeRecentlyModified)
        preferredLanguage = d.string(forKey: Key.language) ?? "system"
        appResourceLocale = appLocale(forCode: preferredLanguage)
    }

    private enum Key {
        static let onboarding = "onboarding_completed"
        static let appearance = "appearance_mode"
        static let autoLock = "auto_lock_timeout"
        static let lockOnBackground = "lock_on_background"
        static let biometric = "biometric_unlock_enabled"
        static let hibp = "hibp_enabled"
        static let icloud = "icloud_sync_enabled"
        static let favicons = "show_website_icons"
        static let clipboard = "clipboard_clear_seconds"
        static let privacyScreen = "hide_in_app_switcher"
        static let homeRecentlyUsed = "home_show_recently_used"
        static let homeRecentlyModified = "home_show_recently_modified"
        static let language = "preferred_language"
    }
}
