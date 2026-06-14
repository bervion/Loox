import SwiftUI
import PhotosUI
import UIKit

/// Pick the background for the current theme: built-in default, none, a curated
/// preset (gradient / animated mesh), or a photo from the library (`PhotosPicker`,
/// no Photos permission needed). Edits persist per-theme.
struct WallpaperGalleryView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var photoItem: PhotosPickerItem?

    private var ref: AppThemeReference { env.theme.settings.theme }
    private var override: Wallpaper? { env.theme.settings.wallpaperOverride(for: ref) }
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    var body: some View {
        Form {
            Section {
                choiceRow(title: Text("Default"), isSelected: override == nil) {
                    env.theme.setWallpaper(nil, for: ref)
                }
                choiceRow(title: Text("None"), isSelected: override == .none) {
                    env.theme.setWallpaper(.none, for: ref)
                }
            }

            presetSection(Text("Gradients"), WallpaperPresets.gradients)
            presetSection(Text("Animated Mesh"), WallpaperPresets.meshes)

            Section {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label { Text("Choose Photo") } icon: { PolarisIcon(Icons.add) }
                }
            } footer: {
                Text("Your photo stays on this device.")
            }
        }
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in importPhoto(item) }
    }

    private func presetSection(_ title: Text, _ presets: [WallpaperPreset]) -> some View {
        Section {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(presets) { preset in
                    presetTile(preset)
                }
            }
            .padding(.vertical, 4)
        } header: {
            title
        }
    }

    private func presetTile(_ preset: WallpaperPreset) -> some View {
        let selected = override == preset.wallpaper
        return Button {
            env.theme.setWallpaper(preset.wallpaper, for: ref)
        } label: {
            WallpaperView(wallpaper: preset.wallpaper, fallbackColor: .gray)
                .frame(height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08),
                                  lineWidth: selected ? 3 : 1))
                .overlay(alignment: .topTrailing) {
                    if selected {
                        PolarisIcon(Icons.checkCircle, size: 20)
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func choiceRow(title: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                title.foregroundStyle(.primary)
                Spacer()
                if isSelected { PolarisIcon(Icons.checkCircle, size: 20).foregroundStyle(Color.accentColor) }
            }
        }
        .buttonStyle(.plain)
    }

    private func importPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            let scaled = WallpaperStorage.downscale(image)
            if let name = WallpaperStorage.save(scaled) {
                env.theme.setWallpaper(.image(fileName: name, settings: WallpaperSettings(dimAlpha: 0.15)), for: ref)
            }
        }
    }
}
