import SwiftUI

/// Appearance hub: theme · accent · auto-night · text size · motion. Edits `ThemeStore`
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
            accentSection
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
            .padding(.vertical, 6)
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
                        PolarisIcon(Icons.checkCircle, size: 18)
                            .foregroundStyle(Color(rgb: preview.accent))
                            .padding(5)
                            .background(Color(rgb: preview.background), in: Circle())
                            .padding(5)
                    }
                }
                .frame(height: 84)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color(rgb: preview.separator),
                                  lineWidth: selected ? 2.5 : 1))
                name.font(.caption).themedForeground().lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: Accent

    private var accentSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: Space.s3)], spacing: Space.s3) {
                ForEach(AccentPreset.allCases) { preset in
                    accentSwatch(preset)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Accent Color")
        } footer: {
            Text("Accent applies instantly across the app. No restart needed.")
        }
        .listRowBackground(VaultColors.surface)
    }

    private func accentSwatch(_ preset: AccentPreset) -> some View {
        // No override defaults to blue (the built-in's native accent), so the active
        // preset always reads as selected even before the user taps one.
        let activeBase = settings.accentOverride(for: current)?.base ?? .blue
        let isSelected = activeBase == preset
        let isDark = env.theme.active.isDark
        return Button {
            env.theme.setAccent(AppAccentColor(base: preset), for: current)
        } label: {
            Circle()
                .fill(Color(rgb: preset.rgb(isDark: isDark)))
                .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
    }

    // MARK: Options

    private var optionsSection: some View {
        Section {
            NavigationLink {
                AutoNightSettingsView()
            } label: {
                Label { Text("Automatic Dark Mode") } icon: { PolarisIcon(Icons.clock) }
            }
            Picker(selection: Binding(get: { settings.fontScale },
                                      set: { env.theme.setFontScale($0) })) {
                ForEach(FontScale.allCases) { Text($0.label).tag($0) }
            } label: {
                Label { Text("Text Size") } icon: { PolarisIcon("ic_text") }
            }
            Toggle(isOn: Binding(get: { settings.reduceMotion },
                                 set: { env.theme.setReduceMotion($0) })) {
                Label { Text("Reduce Motion") } icon: { PolarisIcon(Icons.reveal) }
            }
        }
        .listRowBackground(VaultColors.surface)
    }
}
