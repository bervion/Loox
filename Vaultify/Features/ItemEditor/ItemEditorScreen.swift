import SwiftUI
import Foundation

/// Create or edit an item: title + dynamic fields (add/remove/reorder, change
/// kind, toggle protection, generate passwords). Presented as a sheet.
struct ItemEditorScreen: View {
    let target: EditorTarget
    /// Space to preselect for a new item (the caller's current Space context, e.g. the
    /// Space selected on Home). `nil` → fall back to the primary Space.
    let preselectedFolderId: String?
    @Environment(AppEnvironment.self) private var env
    @Environment(UIStateStore.self) private var uiState
    @Environment(\.dismiss) private var dismiss

    @State private var draft: VaultItem
    @State private var original: VaultItem
    @State private var confirmDiscard = false
    @State private var generatingFieldID: String?
    @State private var scanningFieldID: String?
    @State private var showAttachmentPicker = false
    @State private var showIconPicker = false
    @State private var didApplyDefaultFolder = false

    init(target: EditorTarget, preselectedFolderId: String? = nil) {
        self.target = target
        self.preselectedFolderId = preselectedFolderId
        let item: VaultItem
        switch target {
        case .new(let category):
            item = VaultItem(category: category, title: "", fields: category.fieldTemplate)
        case .edit(let existing):
            item = existing
        case .draft(let prefilled):
            item = prefilled
        }
        _draft = State(initialValue: item)
        _original = State(initialValue: item)
    }

    private var isNew: Bool {
        switch target { case .new, .draft: return true; case .edit: return false }
    }
    private var hasChanges: Bool { draft != original }
    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespaces).isEmpty || draft.fields.contains { !$0.isEmpty }
    }

    var body: some View {
        VaultSheetScaffold(
            // A real (inline) title is required for the nav bar to render its scroll-edge
            // blur material — an empty title leaves the bar background-less, so scrolled
            // content shows through the toolbar pills. Use the item's category name.
            title: draft.category.title,
            leading: {
                // Compact X icon (instead of "Cancel" text) so the centre title fits.
                Button {
                    hasChanges ? (confirmDiscard = true) : dismiss()
                } label: {
                    PolarisIcon(Icons.close, size: 16)
                }
                .accessibilityLabel(Text("Cancel"))
            },
            trailing: {
                EditorHeaderActions(canSave: canSave, save: save)
            }
        ) {
            Form {
                // Space pill (centred) directly above the thumbnail + title, all in one
                // section so they stay close (no inter-section gap). No card — the title field
                // carries its own elevated surface so it reads on the grouped backdrop.
                Section {
                    VStack(spacing: Space.s4) {
                        // Centred pill that hugs its text (Spacers collapse for short names and
                        // let it truncate at the row width for long ones).
                        HStack(spacing: 0) {
                            Spacer(minLength: 0)
                            spaceDropdown
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: Space.s3) {
                            editorThumbnail
                            titleField
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // Match the field cards' left/right edges (their row background spans the full
                // row width), so zero horizontal inset lines the avatar/title up with them.
                .listRowInsets(EdgeInsets(top: Space.s2, leading: 0, bottom: Space.s4, trailing: 0))

                // Login gets grouped sections (Credentials · Websites · Custom · Notes);
                // other categories keep one flat, reorderable field list.
                if draft.category == .login {
                    LoginEditorSections(
                        draft: $draft,
                        onScanTOTP: { scanningFieldID = $0 },
                        onAddAttachment: { showAttachmentPicker = true })
                } else {
                    Section("Fields") {
                        ForEach($draft.fields) { $field in
                            EditorFieldRow(field: $field,
                                           onScanTOTP: { scanningFieldID = field.id })
                        }
                        .onDelete { draft.fields.remove(atOffsets: $0) }
                        .onMove { draft.fields.move(fromOffsets: $0, toOffset: $1) }

                        Menu {
                            ForEach(FieldKind.allCases.filter { $0 != .fileRef }, id: \.self) { kind in
                                Button {
                                    draft.fields.append(DynamicField(label: kind.defaultLabel, kind: kind))
                                } label: {
                                    Label { Text(kind.title) } icon: { PolarisIcon(kind.iconAsset) }
                                }
                            }
                        } label: {
                            Label { Text("Add Field") } icon: { PolarisIcon(Icons.addCircle) }
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)

                        Button { showAttachmentPicker = true } label: {
                            Label { Text("Add Attachment") } icon: { PolarisIcon("ic_attachment") }
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(VaultColors.surface)
                }

                Section("Tags") {
                    TagChipEditor(tags: $draft.tags)
                }
                .listRowBackground(VaultColors.surface)

                RotationReminderSection(rotateDays: $draft.rotateDays)
            }
            // Dismiss the keyboard on scroll. (A Form-level `.onTapGesture` was removed: it
            // swallowed taps on in-row Buttons — e.g. "Add Website" — so their action never
            // fired. TextFields/Menus have their own UIKit gestures and still work; scroll
            // dismissal covers the keyboard.)
            .scrollDismissesKeyboard(.immediately)
            .onAppear {
                // New items default to the primary Space ("My Vault") so they have
                // a home; applied once so it never overrides a user's own pick.
                if isNew, !didApplyDefaultFolder, draft.folderId == nil {
                    // Preselect the caller's Space context (e.g. the Space selected on Home);
                    // when there's none ("All Spaces") fall back to the primary Space.
                    if let target = preselectedFolderId ?? env.repository.folders.first?.id {
                        draft.folderId = target
                        // Fold the auto-applied Space into the baseline too, so it isn't
                        // counted as an unsaved change (otherwise X would prompt "Discard?"
                        // on a pristine new item).
                        original.folderId = target
                    }
                }
                ensureLoginNoteField()
                didApplyDefaultFolder = true
                captureDraftForRestore()
            }
            // Keep the restorable snapshot in sync so a kill mid-edit can resume this draft
            // (sealed under the Vault Key when the app backgrounds). Cleared on dismiss.
            .onChange(of: draft) { captureDraftForRestore() }
            .onDisappear { uiState.editorDraft = nil }
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
            // Full-screen (not a sheet): the camera preview deserves the whole screen.
            .platformFullScreenCover(item: Binding(get: { scanningFieldID.map { GeneratorRequest(id: $0) } },
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
            .sheet(isPresented: $showIconPicker) {
                ItemIconPickerSheet(selected: draft.iconAsset) { draft.iconAsset = $0 }
            }
        }
        // Float the "generate" bubble anchored just below the focused password field. Applied
        // OUTSIDE the scaffold/Form so the overlay never covers the scroll view — covering it
        // would suppress the nav-bar scroll-edge blur and block scroll-to-dismiss-keyboard.
        // The anchor resolves in global space, so positioning stays correct from out here.
        .overlayPreferenceValue(GenerateChipAnchorKey.self) { value in
            GeometryReader { proxy in
                if let value {
                    let rect = proxy[value.bounds]
                    GenerateChip {
                        // Resign the focused field before presenting the generator
                        // sheet. Otherwise it stays first responder behind the sheet
                        // and re-raises the keyboard when a menu opens inside it.
                        dismissKeyboard()
                        generatingFieldID = value.fieldID
                    }
                        .offset(x: rect.minX, y: rect.maxY + 4)
                        .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: value?.fieldID)
        }
    }

    // MARK: Header pieces

    /// Centred Space pill — quick-switch the item's Space via a menu.
    @ViewBuilder private var spaceDropdown: some View {
        Menu {
            ForEach(env.repository.folders) { folder in
                Button { draft.folderId = folder.id } label: {
                    Label { Text(folder.name) } icon: { PolarisIcon(folder.iconAsset) }
                }
            }
        } label: {
            HStack(spacing: Space.s2) {
                if let folder = selectedFolder {
                    FolderBadge(icon: folder.iconAsset, color: folder.color, size: 22)
                    Text(folder.name)
                        .vaultType(.subhead).fontWeight(.semibold).themedForeground()
                        .lineLimit(1).truncationMode(.tail)
                } else {
                    Text("No Space").vaultType(.subhead).themedForeground(.secondary)
                }
                PolarisIcon(Icons.chevronDown, size: 11).themedForeground(.secondary)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .background(VaultColors.fill,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Thumbnail. When the item has a website the favicon wins (icon picker disabled — no
    /// chevron badge); otherwise a custom icon / letter-avatar can be chosen via the menu.
    @ViewBuilder private var editorThumbnail: some View {
        if let website = draft.urlField?.value, !website.isEmpty {
            FaviconView(urlString: website, category: draft.category, size: 56, title: draft.title)
        } else {
            Menu {
                Button { showIconPicker = true } label: {
                    Label { Text("Choose icon") } icon: { PolarisIcon("ic_apps") }
                }
                Button { draft.iconAsset = nil } label: {
                    Label { Text("Letter avatar") } icon: { PolarisIcon("ic_text") }
                }
            } label: {
                ItemThumbnail(title: draft.title, category: draft.category,
                              iconAsset: draft.iconAsset, size: 56)
                    .overlay(alignment: .bottomTrailing) {
                        PolarisIcon(Icons.chevronDown, size: 10)
                            .themedForeground(.secondary)
                            .padding(4)
                            .background(VaultColors.surface, in: Circle())
                            .overlay(Circle().strokeBorder(VaultColors.separatorColor, lineWidth: 0.5))
                            .elevation(.level1)
                            .offset(x: 3, y: 3)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    /// Bold title field on an elevated surface (adapts to light/dark for contrast).
    private var titleField: some View {
        TextField("Enter a title", text: $draft.title)
            .vaultType(.headline)
            .fontWeight(.bold)
            .themedForeground()
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .background(VaultColors.surface,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Resign the first responder so the keyboard hides (on scroll / tap-outside).
    private func dismissKeyboard() {
        PlatformAppearance.dismissKeyboard()
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

    /// Login always shows a Notes section, so guarantee the single `.multiline` note
    /// field exists. Folds the same instance into `original` too, so opening the editor
    /// on a note-less login isn't counted as an unsaved change. Idempotent.
    private func ensureLoginNoteField() {
        guard draft.category == .login,
              !draft.fields.contains(where: { $0.kind == .multiline }) else { return }
        let note = DynamicField(label: "Note", kind: .multiline)
        draft.fields.append(note)
        original.fields.append(note)
    }

    /// Stash the in-progress draft for cross-launch restoration. Only when there's
    /// something worth resuming (a saveable new item, or any edit of an existing one),
    /// so a freshly-opened empty "new item" editor isn't re-presented on relaunch.
    private func captureDraftForRestore() {
        uiState.editorDraft = (canSave || !isNew)
            ? UIStateStore.DraftState(item: draft, isNew: isNew)
            : nil
    }

    private func save() {
        draft.fields.removeAll { $0.isEmpty && $0.label.isEmpty }
        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
            if let field = draft.fields.first(where: { !$0.isEmpty }) {
                // Fall back to the first field's value — but if that's a website, use just the
                // domain (no scheme/path/www) so the title reads "google.com", not the full URL.
                draft.title = (field.kind == .url ? FaviconService.host(from: field.value) : nil) ?? field.value
            } else {
                draft.title = String(localized: draft.category.title)
            }
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

// MARK: - Rotation reminder picker

/// Segmented-style Picker for the per-item rotation cadence.
/// Cadence options: 0 = off, 15 / 30 / 90 days.
private struct RotationReminderSection: View {
    @Binding var rotateDays: Int

    private let options: [(label: LocalizedStringResource, value: Int)] = [
        ("Off", 0),
        ("15 days", 15),
        ("30 days", 30),
        ("90 days", 90),
    ]

    var body: some View {
        Section {
            Picker(selection: $rotateDays) {
                ForEach(options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            } label: {
                Label {
                    Text("Rotation reminder")
                } icon: {
                    PolarisIcon("ic_refresh")
                }
            }
            .pickerStyle(.menu)
        }
        .listRowBackground(VaultColors.surface)
    }
}

private struct GeneratorRequest: Identifiable { let id: String }

/// Trailing header actions (Edit · Save), each a 44pt `HeaderIconButton` so the hit areas
/// match the Home header cluster. A plain `HStack` (no own glass) lets the iOS 26 toolbar wrap
/// both in its single native glass pill — using our `HeaderActionCluster` here would nest a
/// second glass capsule inside the toolbar's, doubling the background. Edit toggles the Form's
/// edit mode (reorder / delete fields); Save commits.
private struct EditorHeaderActions: View {
    let canSave: Bool
    let save: () -> Void
    #if os(iOS)
    @Environment(\.editMode) private var editMode
    private var isEditing: Bool { editMode?.wrappedValue.isEditing == true }
    #endif

    var body: some View {
        HStack(spacing: 0) {
            #if os(iOS)
            // Field reorder is driven by list edit mode — iOS-only (macOS has no edit mode).
            HeaderIconButton(Icons.layoutSection,
                             role: isEditing ? .accent : .iconPrimary,
                             accessibilityLabel: "Edit") {
                withAnimation { editMode?.wrappedValue = isEditing ? .inactive : .active }
            }
            #endif
            HeaderIconButton(Icons.check, role: .accent, accessibilityLabel: "Save", action: save)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
        }
    }
}
