import SwiftUI

/// Create or edit a custom theme: name + base + accent + wallpaper, with a live
/// preview. Saving stores it (App Group) and makes it active.
struct ThemeEditorView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private let editingID: UUID?
    @State private var name: String
    @State private var base: BuiltinTheme
    @State private var accent: AppAccentColor
    @State private var wallpaper: Wallpaper

    init(existing: CustomTheme? = nil) {
        editingID = existing?.id
        _name = State(initialValue: existing?.name ?? "")
        _base = State(initialValue: existing?.base ?? .night)
        _accent = State(initialValue: existing?.accent ?? .default)
        _wallpaper = State(initialValue: existing?.wallpaper ?? .none)
    }

    private var preview: AppTheme { BuiltinThemes.palette(base).recolored(accent: accent.rgb) }

    var body: some View {
        Form {
            Section { previewCard.listRowInsets(EdgeInsets()) }
            .listRowBackground(VaultColors.surface)

            Section { TextField("Theme name", text: $name) } header: { Text("Name") }
            .listRowBackground(VaultColors.surface)

            Section {
                Picker(selection: $base) {
                    ForEach(BuiltinTheme.allCases) { Text($0.displayName).tag($0) }
                } label: { Text("Base") }
            } header: { Text("Base") }
            .listRowBackground(VaultColors.surface)

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: Space.s3)], spacing: Space.s3) {
                    ForEach(AccentPreset.allCases) { preset in accentSwatch(preset) }
                }
                .padding(.vertical, 6)
                ColorPicker(selection: customAccentBinding, supportsOpacity: false) { Text("Custom Color") }
            } header: { Text("Accent Color") }
            .listRowBackground(VaultColors.surface)

            Section {
                wallpaperGrid
            } header: { Text("Background") }
            .listRowBackground(VaultColors.surface)
        }
        .themedFormBackground()
        .navigationTitle(editingID == nil ? "New Theme" : "Edit Theme")
        .themedColorScheme()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Text("Cancel") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: { Text("Save") }
            }
        }
    }

    // MARK: Preview

    private var previewCard: some View {
        ZStack {
            WallpaperView(wallpaper: wallpaper, fallbackColor: Color(rgb: preview.background))
            VStack(spacing: Space.s2) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 10) {
                        Circle().fill(Color(rgb: preview.accent)).frame(width: Metric.iconInline, height: Metric.iconInline)
                        RoundedRectangle(cornerRadius: 4).fill(Color(rgb: preview.primaryText)).frame(width: 90, height: 8)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(rgb: preview.elevatedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
            }
            .padding(Space.gutter)
        }
        .frame(height: 150)
    }

    // MARK: Accent

    private func accentSwatch(_ preset: AccentPreset) -> some View {
        let selected = accent.base == preset && accent.customRGB == nil
        return Button { accent = AppAccentColor(base: preset) } label: {
            Circle().fill(Color(rgb: preset.rgb)).frame(width: Metric.controlSmall, height: Metric.controlSmall)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0.9 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
    }

    private var customAccentBinding: Binding<Color> {
        Binding(get: { Color(rgb: accent.rgb) },
                set: { accent = AppAccentColor(base: accent.base, customRGB: $0.themeRGB) })
    }

    // MARK: Wallpaper

    private var wallpaperGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Space.s3)], spacing: Space.s3) {
            wallpaperTile(.none, label: Text("None"))
            ForEach(WallpaperPresets.all) { preset in
                wallpaperTile(preset.wallpaper, label: nil)
            }
        }
        .padding(.vertical, Space.s1)
    }

    @ViewBuilder private func wallpaperTile(_ value: Wallpaper, label: Text?) -> some View {
        let selected = wallpaper == value
        Button { wallpaper = value } label: {
            WallpaperView(wallpaper: value, fallbackColor: Color(rgb: preview.secondaryBackground))
                .frame(height: 70)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color(rgb: env.theme.active.separator), lineWidth: selected ? 3 : 1))
                .overlay { if let label { label.font(.caption).themedForeground(.secondary) } }
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let theme = CustomTheme(
            id: editingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? appString("My Theme") : name,
            base: base, accent: accent, wallpaper: wallpaper)
        env.theme.saveCustomTheme(theme)
        env.theme.setTheme(.custom(theme.id))
        dismiss()
    }
}
