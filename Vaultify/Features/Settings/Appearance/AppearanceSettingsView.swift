import SwiftUI

/// Appearance hub: theme · accent · background · auto-night · text size · motion.
/// Everything edits `ThemeStore` live and persists to the App Group.
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var settings: ThemeSettings { env.theme.settings }
    private var current: AppThemeReference { settings.theme }

    @State private var editingTheme: CustomTheme?
    @State private var creatingTheme = false
    @State private var importing = false
    @State private var exportDocument: ThemeFileDocument?
    @State private var exporting = false

    var body: some View {
        Form {
            themeSection
            customThemesSection
            accentSection
            backgroundSection
            optionsSection
        }
        .themedFormBackground()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creatingTheme) { NavigationStack { ThemeEditorView() } }
        .sheet(item: $editingTheme) { theme in NavigationStack { ThemeEditorView(existing: theme) } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.vaultTheme]) { handleImport($0) }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .vaultTheme,
                      defaultFilename: exportDocument?.theme.name ?? "Theme") { _ in }
    }

    // MARK: Theme

    private var themeSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                ForEach(BuiltinTheme.allCases) { builtin in
                    themeCard(.builtin(builtin), name: Text(builtin.displayName),
                              preview: BuiltinThemes.palette(builtin))
                }
                ForEach(settings.customThemes) { custom in
                    themeCard(.custom(custom.id), name: Text(custom.name),
                              preview: BuiltinThemes.palette(custom.base).recolored(accent: custom.accent.rgb))
                        .contextMenu {
                            Button { editingTheme = custom } label: { Label { Text("Edit") } icon: { PolarisIcon(Icons.edit) } }
                            Button { exportDocument = ThemeFileDocument(theme: custom); exporting = true } label: {
                                Label { Text("Export") } icon: { PolarisIcon(Icons.exportData) }
                            }
                            Button(role: .destructive) { env.theme.deleteCustomTheme(custom.id) } label: {
                                Label { Text("Delete") } icon: { PolarisIcon(Icons.delete) }
                            }
                        }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Theme")
        }
        .listRowBackground(VaultColors.surface)
    }

    /// A tappable theme card with a mini vault-style preview (cards over a background —
    /// not a chat preview). The whole card is the hit target.
    private func themeCard(_ ref: AppThemeReference, name: Text, preview: AppTheme) -> some View {
        let selected = current == ref
        return Button {
            env.theme.setTheme(ref)
        } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(rgb: preview.background))
                    VStack(spacing: 5) {
                        ForEach(0..<2, id: \.self) { _ in
                            HStack(spacing: 5) {
                                Circle().fill(Color(rgb: preview.accent)).frame(width: 9, height: 9)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(Color(rgb: preview.secondaryText)).frame(height: 5)
                            }
                            .padding(6)
                            .background(Color(rgb: preview.elevatedBackground),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    .padding(8)
                    if selected {
                        PolarisIcon(Icons.checkCircle, size: 18)
                            .foregroundStyle(Color(rgb: preview.accent))
                            .padding(5)
                            .background(Color(rgb: preview.background), in: Circle())
                            .padding(5)
                    }
                }
                .frame(height: 84)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color(rgb: preview.separator),
                                  lineWidth: selected ? 2.5 : 1))
                name.font(.caption).themedForeground().lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var customThemesSection: some View {
        Section {
            Button { creatingTheme = true } label: {
                Label { Text("Create Theme") } icon: { PolarisIcon(Icons.add) }
            }
            Button { importing = true } label: {
                Label { Text("Import Theme") } icon: { PolarisIcon(Icons.importData) }
            }
        } header: {
            Text("Custom Themes")
        } footer: {
            Text("Long-press a custom theme to edit, export, or delete it.")
        }
        .listRowBackground(VaultColors.surface)
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let theme = try? ThemeExchange.decode(data) else { return }
        env.theme.saveCustomTheme(theme)
        env.theme.setTheme(.custom(theme.id))
    }

    // MARK: Accent

    private var accentSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 12)], spacing: 12) {
                ForEach(AccentPreset.allCases) { preset in
                    accentSwatch(preset)
                }
            }
            .padding(.vertical, 6)
            ColorPicker(selection: customAccentBinding, supportsOpacity: false) {
                Text("Custom Color")
            }
        } header: {
            Text("Accent Color")
        }
        .listRowBackground(VaultColors.surface)
    }

    private func accentSwatch(_ preset: AccentPreset) -> some View {
        let isSelected = settings.accentOverride(for: current)?.base == preset
            && settings.accentOverride(for: current)?.customRGB == nil
        return Button {
            env.theme.setAccent(AppAccentColor(base: preset), for: current)
        } label: {
            Circle()
                .fill(Color(rgb: preset.rgb))
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
    }

    private var customAccentBinding: Binding<Color> {
        Binding(
            get: { Color(rgb: env.theme.active.accent) },
            set: { env.theme.setAccent(AppAccentColor(base: .blue, customRGB: $0.themeRGB), for: current) })
    }

    // MARK: Background

    private var backgroundSection: some View {
        Section {
            NavigationLink {
                WallpaperGalleryView()
            } label: {
                HStack(spacing: 14) {
                    WallpaperView(wallpaper: env.theme.wallpaper, fallbackColor: Color(rgb: env.theme.active.background))
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color(rgb: env.theme.active.separator)))
                    Text("Background")
                }
            }
        } header: {
            Text("Background")
        } footer: {
            Text("Shown behind the vault, lock, and onboarding screens.")
        }
        .listRowBackground(VaultColors.surface)
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
