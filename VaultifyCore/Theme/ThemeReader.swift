import Foundation

/// App-Group persistence for `ThemeSettings` + a one-time migration from the legacy
/// `appearance_mode` key. Shared by the app (`ThemeStore`) and the AutoFill extension
/// (which reads the resolved theme directly).
nonisolated enum ThemeReader {
    private static let settingsKey = "theme_settings_v1"
    private static let migratedKey = "theme_settings_migrated_v1"
    private static let legacyAppearanceKey = "appearance_mode"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedConfig.appGroup) ?? .standard
    }

    static func load() -> ThemeSettings {
        migrateIfNeeded()
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(ThemeSettings.self, from: data)
        else { return .default }
        return settings
    }

    static func save(_ settings: ThemeSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    /// Map the old standard-defaults appearance preference into `ThemeSettings` once,
    /// so existing users keep their light/dark/system choice.
    static func migrateIfNeeded() {
        let store = defaults
        guard store.object(forKey: migratedKey) == nil else { return }
        store.set(true, forKey: migratedKey)

        let legacy = UserDefaults.standard.string(forKey: legacyAppearanceKey) ?? "system"
        var settings = ThemeSettings.default
        switch legacy {
        case "light":
            settings.theme = .builtin(.day)
            settings.autoNight = .off
        case "dark":
            settings.theme = .builtin(.night)
            settings.autoNight = .off
        default:
            settings.theme = .builtin(.day)
            settings.nightTheme = .builtin(.night)
            settings.autoNight = .system
        }
        save(settings)
    }
}
