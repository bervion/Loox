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
                        PolarisIcon(Icons.checkCircle, size: 18)
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

    // MARK: Accent

    private var accentSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 50), spacing: Space.s3)], spacing: Space.s3) {
                ForEach(AccentPreset.allCases) { preset in
                    accentSwatch(preset)
                }
            }
            .padding(.vertical, Space.s2)

            // Context preview: the accent is a SYSTEM (fill, tinted, text rank),
            // not a swatch — show all three ranks in both modes so the user can
            // confirm their pick works everywhere without switching appearance.
            HStack(spacing: Space.s3) {
                accentRankPreview(isDark: false, label: "Light")
                accentRankPreview(isDark: true, label: "Dark")
            }
            .padding(.vertical, Space.s2)
        } header: {
            Text("Accent Color")
        } footer: {
            Text("Loox may adjust the selected color slightly to keep text and controls readable.")
        }
        .listRowBackground(VaultColors.surface)
    }

    /// Mini three-rank preview on the given mode's canvas: a filled action,
    /// a tinted action, and an accent link — resolved through the SAME theme
    /// pipeline as the real UI (recolor + contrast guard), so what the user
    /// sees here is exactly what ships. Decorative: hidden from VoiceOver.
    private func accentRankPreview(isDark: Bool, label: LocalizedStringKey) -> some View {
        let activeBase = settings.accentOverride(for: current)?.base ?? .blue
        let base = isDark ? BuiltinThemes.night : BuiltinThemes.day
        let palette = base.recolored(accent: activeBase.rgb(isDark: isDark))
        return VStack(spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("Copy")
                    .vaultType(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color(rgb: palette.accentForeground))
                    .padding(.horizontal, Space.s3).padding(.vertical, 3)
                    .background(Color(rgb: palette.accent), in: Capsule())
                Text("Aa")
                    .vaultType(.caption).fontWeight(.semibold)
                    .foregroundStyle(Color(rgb: palette.accentText))
                    .padding(.horizontal, Space.s3).padding(.vertical, 3)
                    .background(Color(rgb: palette.accentSoft), in: Capsule())
                Text("View details")
                    .vaultType(.caption)
                    .foregroundStyle(Color(rgb: palette.accentText))
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(rgb: palette.elevatedBackground),
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Color(rgb: palette.separator), lineWidth: 1))

            Text(label)
                .vaultType(.caption)
                .themedForeground(.secondary)
        }
        .accessibilityHidden(true)
    }

    private func accentSwatch(_ preset: AccentPreset) -> some View {
        // No override defaults to blue (the built-in's native accent), so the active
        // preset always reads as selected even before the user taps one.
        let activeBase = settings.accentOverride(for: current)?.base ?? .blue
        let isSelected = activeBase == preset
        let isDark = env.theme.active.isDark
        let ringColor = env.theme.active.color(.iconPrimary)
        return Button {
            Haptics.tap()
            env.theme.setAccent(AppAccentColor(base: preset), for: current)
        } label: {
            Circle()
                .fill(Color(rgb: preset.rgb(isDark: isDark)))
                .frame(width: Metric.controlSmall, height: Metric.controlSmall)
                .overlay(Circle().strokeBorder(ringColor.opacity(isSelected ? 0.9 : 0), lineWidth: 2).padding(-3))
                // Pad the 34pt visual swatch to a ≥44pt tap target (Metric.hitMin) —
                // the circle itself stays the design-system control-small size.
                .padding(Space.s2)
                .contentShape(Rectangle())
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
