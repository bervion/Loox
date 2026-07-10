import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Pick an attachment from Files or Photos. Returns the raw bytes + name + ext;
/// the caller seals and stores them via `AttachmentStore`.
struct AttachmentPickerSheet: View {
    let onPicked: (Data, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var error: String?

    var body: some View {
        // Own NavigationStack+toolbar Cancel could render unreliably on macOS sheets —
        // use the shared scaffold instead (guarantees a working close control + sizing).
        VaultSheetScaffold(title: "Add Attachment") {
            List {
                Section {
                    Button { showFileImporter = true } label: {
                        Label { Text("Choose File") } icon: { PolarisIcon("ic_attachment") }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label { Text("Choose Photo") } icon: { PolarisIcon(Icons.image) }
                    }
                    if let error { Text(error).vaultType(.footnote).foregroundStyle(VaultColors.strengthWeak) }
                }
                .listRowBackground(VaultColors.surface)
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                handleFile(result)
            }
            .onChange(of: photoItem) { _, item in Task { await handlePhoto(item) } }
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else {
            error = appString("Couldn’t open the file.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else {
            error = appString("Couldn’t read the file.")
            return
        }
        onPicked(data, url.lastPathComponent, url.pathExtension)
        dismiss()
    }

    private func handlePhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        onPicked(data, "Photo-\(Int(Date().timeIntervalSince1970)).jpg", "jpg")
        dismiss()
    }
}
