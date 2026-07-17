import SwiftUI

/// "General" — the small everyday preferences gathered off the Settings root
/// (Apple-Settings idiom): language, clipboard hygiene, App Switcher privacy,
/// and website icons. Selection prefs open child screens with checkmark rows
/// instead of inline popups.
struct GeneralSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    // Compact-iOS UIKit shell only. When present, a language change runs the
    // branded switch transition (a pushed screen's nav-bar title caches the old
    // language otherwise); the iPad/Mac sidebar (nil) applies it live in place.
    @Environment(AppNavigator.self) private var navigator: AppNavigator?

    private var languageLabel: LocalizedStringResource {
        switch env.settings.preferredLanguage {
        case "en": "English"
        case "vi": "Tiếng Việt"
        default: "System"
        }
    }

    private var clipboardLabel: LocalizedStringResource {
        switch env.settings.clipboardClearSeconds {
        case 15: "After 15s"
        case 30: "After 30s"
        case 60: "After 1 min"
        default: "Never"
        }
    }

    var body: some View {
        @Bindable var settings = env.settings
        let switchTint = Color(rgb: env.theme.active.switchOn)
        Form {
            Section {
                NavigationLink {
                    SettingsSelectionScreen(
                        title: "Language",
                        options: [.init(value: "system", label: "System"),
                                  .init(value: "en", label: "English"),
                                  .init(value: "vi", label: "Tiếng Việt")],
                        selection: $settings.preferredLanguage,
                        // Deferred + branded transition on the UIKit shell; the
                        // sidebar keeps the plain live apply.
                        onCommit: navigator.map { nav in { nav.switchLanguage(to: $0) } })
                } label: {
                    LabeledContent {
                        Text(languageLabel)
                    } label: {
                        Label { Text("Language") } icon: { SettingsIconBadge(systemName: "globe", tint: SettingsBadgeTint.blue) }
                    }
                }
                NavigationLink {
                    SettingsSelectionScreen(
                        title: "Clear clipboard",
                        options: [.init(value: 15, label: "After 15s"),
                                  .init(value: 30, label: "After 30s"),
                                  .init(value: 60, label: "After 1 min"),
                                  .init(value: 0, label: "Never")],
                        selection: $settings.clipboardClearSeconds)
                } label: {
                    LabeledContent {
                        Text(clipboardLabel)
                    } label: {
                        Label { Text("Clear clipboard") } icon: { SettingsIconBadge(systemName: "doc.on.clipboard.fill", tint: SettingsBadgeTint.gray) }
                    }
                }
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Toggle(isOn: $settings.hideInAppSwitcher) {
                    Label { Text("Hide contents in App Switcher") } icon: { SettingsIconBadge(systemName: "eye.slash.fill", tint: SettingsBadgeTint.indigo) }
                }
                .tint(switchTint)
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Toggle(isOn: $settings.showWebsiteIcons) {
                    Label { Text("Show website icons") } icon: { SettingsIconBadge(systemName: "safari.fill", tint: SettingsBadgeTint.blue) }
                }
                .tint(switchTint)
            } footer: {
                Text("Uses Google to fetch site icons as login avatars. This reveals the sites you have logins for to Google; turn off to keep everything on-device.")
            }
            .listRowBackground(VaultColors.surface)

            Section {
                Toggle(isOn: $settings.analyticsEnabled) {
                    Label { Text("Share anonymous usage statistics") } icon: { SettingsIconBadge(systemName: "chart.bar.fill", tint: SettingsBadgeTint.green) }
                }
                .tint(switchTint)
            } footer: {
                Text("Counts which features are used to help improve Loox. Never your vault contents, item names, websites, or search terms. Not linked to your identity.")
            }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .toggleStyle(.switch)
        .navigationTitle("General")
        .platformNavigationBarTitleDisplayMode(.inline)
    }
}
