import SwiftUI

/// Walks the user through turning Loox on as an AutoFill provider.
///
/// The switch itself lives in iOS Settings, where no spotlight can follow, so
/// each step embeds a stand-in for the row the user is about to look for. The
/// deep link still does the navigating — this only makes the destination
/// recognizable, which is where people got lost.
struct AutoFillSetupGuide: View {
    /// Runs the existing deep link (`ASSettingsHelper`), owned by the caller so
    /// this view stays free of AuthenticationServices.
    let openSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme

    var body: some View {
        TutorialGuideSheet(
            title: "Set up AutoFill",
            intro: "Once Loox is on, iOS offers your saved logins above the keyboard in other apps and Safari.",
            steps: [
                TutorialGuideStep("Open Settings, then General, then AutoFill & Passwords.") {
                    settingsRowPreview(title: "AutoFill & Passwords",
                                       systemName: "key.fill",
                                       tint: SettingsBadgeTint.gray,
                                       trailing: .chevron)
                },
                TutorialGuideStep("Turn on AutoFill Passwords and Passcodes.") {
                    settingsRowPreview(title: "AutoFill Passwords and Passcodes",
                                       systemName: "rectangle.and.pencil.and.ellipsis",
                                       tint: SettingsBadgeTint.blue,
                                       trailing: .toggleOn)
                },
                TutorialGuideStep("Tick Loox in the provider list. Leave iCloud Passwords on if you still use it.") {
                    settingsRowPreview(title: "Loox",
                                       brandMark: true,
                                       tint: SettingsBadgeTint.blue,
                                       trailing: .check)
                },
            ]
        ) {
            VStack(spacing: Space.s3) {
                Button {
                    openSettings()
                    dismiss()
                } label: {
                    Text("Open Settings").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedProminent)
                Button { dismiss() } label: {
                    Text("Later").frame(maxWidth: .infinity)
                }
                .buttonStyle(.themedTinted)
            }
        }
        .themedColorScheme()
    }

    /// What the row looks like in iOS Settings. A stand-in, not a screenshot:
    /// it follows the user's theme and language, and it cannot go stale in a
    /// dark-mode or localization pass the way a bundled image would.
    private enum RowTrailing { case chevron, toggleOn, check }

    private func settingsRowPreview(title: LocalizedStringResource,
                                    systemName: String? = nil,
                                    brandMark: Bool = false,
                                    tint: Color,
                                    trailing: RowTrailing) -> some View {
        HStack(spacing: Space.s3) {
            if brandMark {
                // The square brand symbol, not the wide wordmark: this stands in
                // for an app icon in a provider list.
                Image("BrandSymbol")
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .frame(width: Metric.iconTile, height: Metric.iconTile)
                    .background(VaultColors.fill)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            } else if let systemName {
                SettingsIconBadge(systemName: systemName, tint: tint)
            }
            Text(title.inAppLocalized)
                .vaultType(.body)
                .themedForeground()
                .lineLimit(2)
            Spacer(minLength: 0)
            switch trailing {
            case .chevron:
                PolarisIcon(Icons.chevronRight, size: 13).themedForeground(.tertiary)
            case .toggleOn:
                // A drawn switch, not a live Toggle: this row is a picture of
                // another app's screen and must never look interactive.
                Capsule()
                    .fill(Color(rgb: theme.switchOn))
                    .frame(width: 44, height: 26)
                    .overlay(alignment: .trailing) {
                        Circle().fill(.white).frame(width: 22, height: 22).padding(2)
                    }
            case .check:
                PolarisIcon(Icons.check, size: 15)
                    .foregroundStyle(Color(rgb: theme.accent))
            }
        }
        .padding(Space.s3)
        .background(VaultColors.surface)
        .vaultCornerRadius(Radius.md)
    }
}
