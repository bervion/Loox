import SwiftUI

/// Appearance hub: theme (Light/Dark) · auto-night · text size · motion.
/// Accent selection is retired (260713): the app ships the brand colors only
/// (the engine + presets remain for a future re-enable, like wallpapers). Edits `ThemeStore`
/// live and persists to the App Group.
///
/// Simplified to the Design-System surface: flat themed backgrounds (no wallpaper picker),
/// the seven preset accents (no custom RGB), and the built-in Day / Night themes. The
/// wallpaper engine + custom-theme editor code is retained but no longer surfaced here.
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var settings: ThemeSettings { env.theme.settings }
    private var current: AppThemeReference { settings.theme }

    var body: some View {
        Form {
            themeSection
            optionsSection
        }
        .themedFormBackground()
        .navigationTitle("Appearance")
        .platformNavigationBarTitleDisplayMode(.inline)
    }

    // MARK: Theme

    private var themeSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Space.s3)], spacing: Space.s3) {
                ForEach(BuiltinTheme.selectable) { builtin in
                    themeCard(.builtin(builtin), name: Text(builtin.displayName),
                              preview: BuiltinThemes.palette(builtin))
                }
            }
            .padding(.vertical, Space.s2)
        } header: {
            Text("Theme")
        }
        .listRowBackground(VaultColors.surface)
    }

    /// A tappable theme card with a mini vault-style preview (cards over a background).
    /// The whole card is the hit target.
    private func themeCard(_ ref: AppThemeReference, name: Text, preview: AppTheme) -> some View {
        let selected = current == ref
        return Button {
            Haptics.tap()
            env.theme.setTheme(ref)
        } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Color(rgb: preview.background))
                    VStack(spacing: 5) {
                        ForEach(0..<2, id: \.self) { _ in
                            HStack(spacing: 5) {
                                Circle().fill(Color(rgb: preview.accent)).frame(width: 9, height: 9)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color(rgb: preview.secondaryText)).frame(height: 5)
                            }
                            .padding(Space.s1)
                            .background(Color(rgb: preview.elevatedBackground),
                                        in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                        }
                    }
                    .padding(Space.s2)
                    if selected {
                        VaultIcon(Icons.checkCircle, size: 18)
                            .foregroundStyle(Color(rgb: preview.accent))
                            .padding(5)
                            .background(Color(rgb: preview.background), in: Circle())
                            .padding(5)
                    }
                }
                .frame(height: 84)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    // Live theme accent, not the static asset accent — the ring must
                    // follow the active preset the moment the user switches it.
                    .strokeBorder(selected ? env.theme.uiTint : Color(rgb: preview.separator),
                                  lineWidth: selected ? 2.5 : 1))
                name.vaultType(.caption).themedForeground().lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Options

    private var optionsSection: some View {
        Section {
            NavigationLink {
                AutoNightSettingsView()
            } label: {
                Label { Text("Automatic Dark Mode") } icon: { VaultIcon(Icons.clock) }
            }
            Picker(selection: Binding(get: { settings.fontScale },
                                      set: { env.theme.setFontScale($0) })) {
                ForEach(FontScale.allCases) { Text($0.label).tag($0) }
            } label: {
                Label { Text("Text Size") } icon: { VaultIcon("ic_text") }
            }
            Toggle(isOn: Binding(get: { settings.reduceMotion },
                                 set: { env.theme.setReduceMotion($0) })) {
                Label { Text("Reduce Motion") } icon: { VaultIcon(Icons.reveal) }
            }
        }
        .listRowBackground(VaultColors.surface)
    }
}
