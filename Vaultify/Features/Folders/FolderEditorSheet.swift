import SwiftUI

/// Create or edit a folder ("Space"): name + icon + color. In edit mode it also
/// offers delete (members move to Unfiled, never deleted). Presented as a sheet.
struct FolderEditorSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    /// nil = create a new folder; non-nil = edit this folder.
    let folder: Folder?
    /// Called with the saved folder's id (created or edited).
    var onSaved: (String) -> Void

    @State private var name: String
    @State private var icon: String
    @State private var color: FolderColor
    @State private var confirmDelete = false

    init(folder: Folder?, onSaved: @escaping (String) -> Void = { _ in }) {
        self.folder = folder
        self.onSaved = onSaved
        _name = State(initialValue: folder?.name ?? "")
        _icon = State(initialValue: folder?.iconAsset ?? "ic_folder")
        _color = State(initialValue: folder?.color ?? .blue)
    }

    private var isEditing: Bool { folder != nil }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VaultSheetScaffold(
            title: isEditing ? "Edit Space" : "New Space",
            trailing: {
                Button("Save", action: save).disabled(!canSave).fontWeight(.semibold)
            }
        ) {
            Form {
                Section { TextField("Space name", text: $name).autocorrectionDisabled() }
                .listRowBackground(VaultColors.surface)
                Section {
                    IconColorPicker(icon: $icon, color: $color)
                        .listRowInsets(EdgeInsets(top: Space.s3, leading: Space.s4, bottom: Space.s3, trailing: Space.s4))
                }
                .listRowBackground(VaultColors.surface)
                if isEditing {
                    Section {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label { Text("Delete Space") } icon: { PolarisIcon(Icons.trash) }
                        }
                    }
                    .listRowBackground(VaultColors.surface)
                }
            }
            .confirmationDialog("Delete this Space? Items move to Unfiled.",
                                isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Space", role: .destructive, action: delete)
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            if let folder {
                var updated = folder
                updated.name = trimmed
                updated.iconAsset = icon
                updated.color = color
                try env.repository.updateFolder(updated)
                onSaved(folder.id)
            } else {
                let id = try env.repository.addFolder(name: trimmed, icon: icon, color: color)
                onSaved(id)
            }
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
        }
    }

    private func delete() {
        guard let folder else { return }
        try? env.repository.deleteFolder(folder)
        Haptics.error()
        dismiss()
    }
}
