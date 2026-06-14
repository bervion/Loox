import SwiftUI

/// Create or edit an item: title + dynamic fields (add/remove/reorder, change
/// kind, toggle protection, generate passwords). Presented as a sheet.
struct ItemEditorScreen: View {
    let target: EditorTarget
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var draft: VaultItem
    @State private var original: VaultItem
    @State private var confirmDiscard = false
    @State private var generatingFieldID: String?
    @State private var scanningFieldID: String?
    @State private var showAttachmentPicker = false
    @State private var showFolderPicker = false
    @State private var didApplyDefaultFolder = false

    init(target: EditorTarget) {
        self.target = target
        let item: VaultItem
        switch target {
        case .new(let category):
            item = VaultItem(category: category, title: "", fields: category.fieldTemplate)
        case .edit(let existing):
            item = existing
        }
        _draft = State(initialValue: item)
        _original = State(initialValue: item)
    }

    private var isNew: Bool { if case .new = target { return true } else { return false } }
    private var hasChanges: Bool { draft != original }
    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty || draft.fields.contains { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        CategoryBadge(category: draft.category, size: 38)
                        TextField("Title", text: $draft.title)
                            .font(.headline)
                    }
                }

                Section("Fields") {
                    ForEach($draft.fields) { $field in
                        EditorFieldRow(field: $field,
                                       onGenerate: { generatingFieldID = field.id },
                                       onScanTOTP: { scanningFieldID = field.id })
                    }
                    .onDelete { draft.fields.remove(atOffsets: $0) }
                    .onMove { draft.fields.move(fromOffsets: $0, toOffset: $1) }

                    Menu {
                        ForEach(FieldKind.allCases.filter { $0 != .fileRef }, id: \.self) { kind in
                            Button {
                                draft.fields.append(DynamicField(label: String(localized: kind.title), kind: kind))
                            } label: {
                                Label { Text(kind.title) } icon: { PolarisIcon(kind.iconAsset) }
                            }
                        }
                    } label: {
                        Label { Text("Add Field") } icon: { PolarisIcon(Icons.addCircle) }
                    }

                    Button { showAttachmentPicker = true } label: {
                        Label { Text("Add Attachment") } icon: { PolarisIcon("ic_attachment") }
                    }
                }

                Section("Space") {
                    Button { showFolderPicker = true } label: {
                        HStack(spacing: 12) {
                            if let folder = selectedFolder {
                                FolderBadge(icon: folder.iconAsset, color: folder.color, size: 30)
                                Text(folder.name).foregroundStyle(.primary)
                            } else {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(.tertiarySystemFill)).frame(width: 30, height: 30)
                                Text("None").foregroundStyle(.secondary)
                            }
                            Spacer()
                            PolarisIcon(Icons.chevronRight, size: 14).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Tags") {
                    TagChipEditor(tags: $draft.tags)
                }
            }
            .navigationTitle(isNew ? String(localized: draft.category.title) : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // New items default to the primary Space ("My Vault") so they have
                // a home; applied once so it never overrides a user's own pick.
                if isNew, !didApplyDefaultFolder, draft.folderId == nil,
                   let primary = env.repository.folders.first {
                    draft.folderId = primary.id
                }
                didApplyDefaultFolder = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { hasChanges ? (confirmDiscard = true) : dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave).fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
            }
            .sheet(item: Binding(get: { generatingFieldID.map { GeneratorRequest(id: $0) } },
                                 set: { generatingFieldID = $0?.id })) { request in
                PasswordGeneratorSheet { password in
                    if let index = draft.fields.firstIndex(where: { $0.id == request.id }) {
                        draft.fields[index].value = password
                    }
                }
            }
            .sheet(item: Binding(get: { scanningFieldID.map { GeneratorRequest(id: $0) } },
                                 set: { scanningFieldID = $0?.id })) { request in
                TOTPScannerSheet { secret in
                    if let index = draft.fields.firstIndex(where: { $0.id == request.id }) {
                        draft.fields[index].value = secret
                    }
                }
            }
            .sheet(isPresented: $showAttachmentPicker) {
                AttachmentPickerSheet { data, name, ext in addAttachment(data, name: name, ext: ext) }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerSheet(folderId: $draft.folderId)
            }
        }
    }

    /// The folder the draft item currently belongs to, if any.
    private var selectedFolder: Folder? {
        guard let id = draft.folderId else { return nil }
        return env.repository.folders.first { $0.id == id }
    }

    /// Seal the picked bytes via `AttachmentStore` and append a `.fileRef` field
    /// holding the (non-secret) metadata pointer.
    private func addAttachment(_ data: Data, name: String, ext: String) {
        guard let meta = try? env.attachmentStore.save(data, name: name, ext: ext) else {
            Haptics.error(); return
        }
        draft.fields.append(DynamicField(label: name, kind: .fileRef, value: meta.encoded()))
        Haptics.success()
    }

    private func save() {
        draft.fields.removeAll { $0.isEmpty && $0.label.isEmpty }
        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
            draft.title = draft.fields.first { !$0.isEmpty }?.value ?? String(localized: draft.category.title)
        }
        do {
            if isNew { try env.repository.add(draft) } else { try env.repository.update(draft) }
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
        }
    }
}

private struct GeneratorRequest: Identifiable { let id: String }
