import CloudKit
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
    @State private var showCardScanner = false
    @State private var didApplyDefaultFolder = false
    /// Persona-scoped username suggestions for a new login (computed once on appear).
    /// Empty under a strictAnonymous persona with no own profile (INV-R03 fail-safe).
    @State private var usernameSuggestions: [String] = []
    // Private-email provisioning (create-login flow). Rendering the chip never
    // allocates a backend alias (INV-PE03) — provisioning runs only on tap.
    @State private var creatingAlias = false
    @State private var pendingAliasID: String?
    @State private var aliasMissingEmail = false
    @State private var aliasError = false
    @State private var showEmailSuggestions = false

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
                    PolarisIcon(Icons.close, size: Metric.iconInline)
                }
                .accessibilityLabel(Text("Cancel"))
            },
            trailing: {
                EditorHeaderActions(canSave: canSave, save: save)
            }
        ) {
            Form {
                // Space pill (left-aligned, matching the detail screen) directly above the
                // thumbnail + title, all in one section so they stay close (no inter-section
                // gap). No card — the title field carries its own elevated surface.
                Section {
                    VStack(alignment: .leading, spacing: Space.s4) {
                        // Left-aligned pill that hugs its text (trailing Spacer pushes it left;
                        // it truncates at the row width for long names).
                        HStack(spacing: 0) {
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

                // Email suggestions moved OFF the page: they now live behind the
                // floating "Private Email" bubble that appears while the
                // username/email field is focused (same pattern as the password
                // generate bubble) and open as a bottom sheet — the old always-on
                // horizontal chip strip washed into the background and scrolled
                // awkwardly above the form.

                // Login gets grouped sections (Credentials · Websites · Custom · Notes);
                // other categories keep one flat, reorderable field list.
                if draft.category == .login {
                    LoginEditorSections(
                        draft: $draft,
                        onScanTOTP: { scanningFieldID = $0 },
                        onAddAttachment: { showAttachmentPicker = true })
                } else {
                    Section("Fields") {
                        // Scan Card: only offered for the Card template, and only where
                        // VisionKit live-text scanning can actually run (hidden on the
                        // Simulator) — manual entry below always remains available.
                        if draft.category == .card, CardScannerSheet.isAvailable {
                            Button { showCardScanner = true } label: {
                                // SF Symbol here is a user-granted exception scoped to the
                                // payment-card context only (`creditcard.viewfinder` reads
                                // as a card-scan affordance better than any Polaris asset;
                                // see `docs/design-dna-standard.md` acceptance-matrix note).
                                Label {
                                    Text("Scan Card")
                                } icon: {
                                    Image(systemName: "creditcard.viewfinder")
                                        .font(.system(size: 17))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach($draft.fields) { $field in
                            EditorFieldRow(field: $field,
                                           onScanTOTP: { scanningFieldID = field.id },
                                           category: draft.category,
                                           siblingCardNumber: cardNumberFieldValue)
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
                            // Full-width label so the WHOLE row is tappable — a bare `Label`
                            // only registers taps on its text/icon, leaving the rest of the
                            // row dead (same fix already applied in `LoginEditorSections`).
                            Label { Text("Add Field") } icon: { PolarisIcon(Icons.addCircle) }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.button)
                        .buttonStyle(.plain)
                        .menuIndicator(.hidden)

                        Button { showAttachmentPicker = true } label: {
                            Label { Text("Add Attachment") } icon: { PolarisIcon("ic_attachment") }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(VaultColors.surface)
                }

                Section("Tags") {
                    TagChipEditor(tags: $draft.tags)
                }
                .listRowBackground(VaultColors.surface)

                // Rotation only means something for items that actually carry a
                // password — an identity or note has nothing to rotate.
                if draft.fields.contains(where: { $0.kind == .password && !$0.isEmpty }) {
                    RotationReminderSection(rotateDays: $draft.rotateDays)
                }
            }
            // Dismiss the keyboard on scroll. (A Form-level `.onTapGesture` was removed: it
            // swallowed taps on in-row Buttons — e.g. "Add Website" — so their action never
            // fired. TextFields/Menus have their own UIKit gestures and still work; scroll
            // dismissal covers the keyboard.)
            .scrollDismissesKeyboard(.immediately)
            .analyticsScreen(isNew ? "item_editor_new" : "item_editor_edit")
            .onAppear {
                // New items default to the primary Space ("My Vault") so they have
                // a home; applied once so it never overrides a user's own pick.
                if isNew, !didApplyDefaultFolder, draft.folderId == nil {
                    // Preselect the caller's Space context (e.g. the Space selected on Home);
                    // when there's none ("All Spaces") fall back to the primary Space.
                    if let target = preselectedFolderId ?? env.repository.primarySpaceId {
                        draft.folderId = target
                        // Fold the auto-applied Space into the baseline too, so it isn't
                        // counted as an unsaved change (otherwise X would prompt "Discard?"
                        // on a pristine new item).
                        original.folderId = target
                    }
                }
                ensureLoginNoteField()
                if isNew, draft.category == .login {
                    usernameSuggestions = env.repository.usernameSuggestions()
                }
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
            // Full-screen (not a sheet): the camera preview deserves the whole screen.
            .platformFullScreenCover(isPresented: $showCardScanner) {
                CardScannerSheet { result in applyCardScan(result) }
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
                    Group {
                        if value.kind == .password {
                            GenerateChip {
                                // Resign the focused field before presenting the generator
                                // sheet. Otherwise it stays first responder behind the sheet
                                // and re-raises the keyboard when a menu opens inside it.
                                dismissKeyboard()
                                generatingFieldID = value.fieldID
                            }
                        } else if privateEmailBubbleAvailable {
                            PrivateEmailChip {
                                dismissKeyboard()
                                showEmailSuggestions = true
                            }
                        }
                    }
                    .offset(x: rect.minX, y: rect.maxY + 4)
                    .transition(.scale(scale: 0.9, anchor: .topLeading).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: value?.fieldID)
        }
        // Email suggestions: create a per-site private email (relay), reuse an
        // existing alias (also the "switch back to private email" path when the
        // login currently holds the real address), or fill a plain username
        // suggestion. Opened from the floating bubble on the focused field.
        .sheet(isPresented: $showEmailSuggestions) { emailSuggestionSheet }
    }

    /// Whether the floating private-email bubble has anything to offer. Hidden once
    /// the Credentials field already holds an attached alias — that state gets its
    /// own recognition + detach treatment inside `LoginEditorSections`.
    private var privateEmailBubbleAvailable: Bool {
        draft.category == .login && attachedPrivateEmailMatch == nil
            && ((RelayFeature.activeAliasesEnabled && (createAliasAvailable || !aliasSuggestions.isEmpty))
                || (isNew && !usernameSuggestions.isEmpty))
    }

    /// Bottom sheet listing the private-email actions as full rows — the previous
    /// horizontal chip strip washed into the grouped background and clipped long
    /// addresses; rows give each suggestion honest width and a clear tap target.
    private var emailSuggestionSheet: some View {
        VaultSheetScaffold(title: "Suggested email",
                           leading: { EmptyView() },
                           trailing: { SheetDismissButton("Done") }) {
            List {
                if RelayFeature.activeAliasesEnabled, createAliasAvailable {
                    Section {
                        Button { createPrivateEmail() } label: {
                            HStack(spacing: Space.s3) {
                                if creatingAlias {
                                    ProgressView().controlSize(.small)
                                } else {
                                    PolarisIcon(Icons.mail, size: Metric.iconInline).themedForeground(.accentText)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Create private email").vaultType(.body).themedForeground(.accent)
                                    if let host = draft.autofillHost {
                                        Text("Unique for \(host)")
                                            .vaultType(.caption).themedForeground(.secondary)
                                    }
                                }
                            }
                        }
                        .disabled(creatingAlias)
                    }
                    .listRowBackground(VaultColors.surface)
                }
                if !aliasSuggestions.isEmpty {
                    // Reuse before create: an existing alias for this site/persona
                    // is never re-minted.
                    Section("Reuse") {
                        ForEach(aliasSuggestions) { alias in
                            Button {
                                selectAliasSuggestion(alias)
                                showEmailSuggestions = false
                            } label: {
                                Text(verbatim: AliasAddress.display(
                                    localPart: alias.localPart, status: alias.status,
                                    relayDomain: alias.emailDomain))
                                    .vaultType(.body).themedForeground(.primary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    .listRowBackground(VaultColors.surface)
                }
                if isNew, !usernameSuggestions.isEmpty {
                    Section("Usernames") {
                        ForEach(usernameSuggestions, id: \.self) { value in
                            Button {
                                applyUsernameSuggestion(value)
                                showEmailSuggestions = false
                            } label: {
                                Text(verbatim: value)
                                    .vaultType(.body).themedForeground(.primary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    .listRowBackground(VaultColors.surface)
                }
            }
            .alert(Text("Add an email first"), isPresented: $aliasMissingEmail) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Add an email to this identity’s profile. That’s where your aliases forward to.")
            }
            .alert(Text("Couldn’t reach the relay"), isPresented: $aliasError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your connection and iCloud, then try again.")
            }
        }
        .platformPresentationDetents([.medium, .large])
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
                SpaceIdentityLine(folder: selectedFolder, badgeSize: 22)
                PolarisIcon(Icons.chevronDown, size: 11).themedForeground(.secondary)
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            // Same white pill as the detail header — the gray fill here read
            // as a disabled control next to it.
            .background(VaultColors.surface,
                        in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Thumbnail. When the item has a website the favicon wins (icon picker disabled — no
    /// chevron badge); otherwise a custom icon / letter-avatar can be chosen via the menu.
    @ViewBuilder private var editorThumbnail: some View {
        Menu {
            // Default: the category type icon (or the website favicon for logins).
            // Menu glyphs use the single-tone category icon so all three rows share
            // the line-icon weight/padding (the duotone glyph reads oversized here).
            Button { draft.iconAsset = nil } label: {
                Label { Text("Default") } icon: { PolarisIcon(draft.category.iconAsset, size: Metric.iconInline) }
            }
            Button { draft.iconAsset = ItemAvatarStyle.monogramToken } label: {
                Label { Text("Letter avatar") } icon: { PolarisIcon("ic_text", size: Metric.iconInline) }
            }
            Button { showIconPicker = true } label: {
                Label { Text("Choose icon") } icon: { PolarisIcon("ic_apps", size: Metric.iconInline) }
            }
        } label: {
            FaviconView(urlString: draft.urlField?.value, category: draft.category, size: 56,
                        title: draft.title, iconAsset: draft.iconAsset)
                .overlay(alignment: .bottomTrailing) {
                    PolarisIcon(Icons.chevronDown, size: 10)
                        .themedForeground(.secondary)
                        .padding(Space.s1)
                        .background(VaultColors.surface, in: Circle())
                        .overlay(Circle().strokeBorder(VaultColors.separatorColor, lineWidth: 0.5))
                        .elevation(.level1)
                        .offset(x: 3, y: 3)
                }
        }
        .buttonStyle(.plain)
    }

    /// Bold title field on an elevated surface (adapts to light/dark for contrast).
    private var titleField: some View {
        TextField("Enter a title", text: $draft.title)
            .accessibilityIdentifier("item.editor.title")
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

    /// The card template's Card Number field value, if present — passed to `EditorFieldRow`
    /// so the sibling Security Code field can resolve its CVV length from the detected brand.
    private var cardNumberFieldValue: String? {
        draft.fields.first { $0.kind == .monospace && $0.label == "Card Number" }?.value
    }

    /// Fills the Card Number/Expiry/Cardholder fields from a completed camera scan. Only
    /// ever fills a field that's currently empty — a scan never overwrites something the
    /// user already typed. The scanner already fired its own capture haptic; no second one
    /// here (one physical event, one haptic).
    private func applyCardScan(_ result: CardScanResult) {
        func fill(label: String, kind: FieldKind, with newValue: String?) {
            guard let newValue, !newValue.isEmpty,
                  let index = draft.fields.firstIndex(where: { $0.kind == kind && $0.label == label }),
                  draft.fields[index].value.isEmpty else { return }
            draft.fields[index].value = newValue
        }
        fill(label: "Card Number", kind: .monospace, with: result.numberDigits)
        fill(label: "Expiry", kind: .text, with: result.expiry)
        fill(label: "Cardholder", kind: .text, with: result.cardholderName)
    }

    /// Fill the login's username (or email) field from a tapped suggestion. Sets
    /// only that one field — never auto-writes on its own, so a strictAnonymous
    /// persona with no suggestion simply sees no chips.
    private func applyUsernameSuggestion(_ value: String) {
        if let idx = draft.fields.firstIndex(where: { $0.kind == .username }) {
            draft.fields[idx].value = value
        } else if let idx = draft.fields.firstIndex(where: { $0.kind == .email }) {
            draft.fields[idx].value = value
        }
    }

    // MARK: Private email (editor integration)

    /// Live reuse candidates for this draft's site, scoped to the active persona.
    private var aliasSuggestions: [EmailAlias] {
        env.repository.aliasSuggestions(forItem: isNew ? nil : draft.id,
                                        host: draft.autofillHost)
    }

    /// Whether the Credentials email/username field already holds one of the
    /// active persona's aliases — while true, the top suggestion row hides (the
    /// attached-alias recognition + detach lives in `LoginEditorSections` instead).
    private var attachedPrivateEmailMatch: PrivateEmailMatch? {
        guard draft.category == .login else { return nil }
        for field in draft.fields where field.kind == .email || field.kind == .username {
            if let match = PrivateEmailMatch.resolve(kind: field.kind, value: field.value,
                                                     repository: env.repository) {
                return match
            }
        }
        return nil
    }

    /// Same capability gate `PersonaAliasesScreen` uses for alias creation
    /// (INV-CAP-02: never at startup, contextual only) — reused here so the
    /// inline "Create private email" affordance hides cleanly instead of
    /// offering a tap that's guaranteed to fail while the relay is unavailable.
    private var createAliasAvailable: Bool {
        env.capabilities.availability(.privateEmail, operation: .create) == .available
    }

    /// Reserve → activate a per-site alias and fill it in. On failure the alias
    /// stays `reserved` (resumable, manageable in Private Email) — never
    /// auto-deleted, and the address is never shown as usable (INV-PE02). No
    /// success haptic on the happy path — matches `PersonaAliasesScreen`'s own
    /// alias-creation flow, which stays silent on success and only surfaces a
    /// haptic (`Haptics.error()`) on failure.
    private func createPrivateEmail() {
        guard let persona = env.repository.activePersona else { return }
        guard env.repository.newAliasDestination(for: persona) != nil else {
            aliasMissingEmail = true
            return
        }
        creatingAlias = true
        let host = draft.autofillHost
        // An existing item's id is already stable — bind immediately instead of
        // deferring to save (which only ever runs `bindPendingAlias()` for new items).
        let boundItemId = isNew ? nil : draft.id
        Task {
            defer { creatingAlias = false }
            do {
                let id = try env.repository.createPerSiteAlias(for: persona, boundItemId: boundItemId,
                                                               domain: host,
                                                               domainID: PrivateEmailDomainDefault.domainID)
                guard let alias = env.repository.aliases.first(where: { $0.id == id }) else { return }
                try await env.relay.activate(alias)
                if let live = env.repository.aliases.first(where: { $0.id == id }),
                   live.status == .active {
                    fillEmail(AliasAddress.display(localPart: live.localPart, status: live.status,
                                                   relayDomain: live.emailDomain))
                    if isNew { pendingAliasID = id }
                    showEmailSuggestions = false   // filled — the sheet's job is done
                }
            } catch {
                aliasError = true
                Haptics.error()
            }
        }
    }

    /// Fill a reused alias suggestion into the login's email field. An existing
    /// item's id is already stable, so an unbound reusable alias binds right
    /// away (mirrors `createPrivateEmail`'s immediate bind); a brand-new item
    /// defers binding to `bindPendingAlias()` at save, since it has no id yet.
    private func selectAliasSuggestion(_ alias: EmailAlias) {
        fillEmail(AliasAddress.display(localPart: alias.localPart, status: alias.status,
                                       relayDomain: alias.emailDomain))
        guard alias.boundItemId == nil else { return }
        if isNew {
            pendingAliasID = alias.id
        } else {
            var updated = alias
            updated.boundItemId = draft.id
            if updated.boundDomain == nil { updated.boundDomain = draft.autofillHost }
            try? env.repository.updateAlias(updated)
        }
    }

    /// Put the alias address where AutoFill will use it: email field, else
    /// username field, else a new Email field.
    private func fillEmail(_ value: String) {
        if let idx = draft.fields.firstIndex(where: { $0.kind == .email }) {
            draft.fields[idx].value = value
        } else if let idx = draft.fields.firstIndex(where: { $0.kind == .username }) {
            draft.fields[idx].value = value
        } else {
            draft.fields.insert(DynamicField(label: "Email", kind: .email, value: value), at: 0)
        }
    }

    /// Bind the freshly provisioned (or reused-unbound) alias to the saved login,
    /// so returning to this site reuses this exact address (never re-mints).
    private func bindPendingAlias() {
        guard let id = pendingAliasID,
              var alias = env.repository.aliases.first(where: { $0.id == id }),
              alias.boundItemId == nil else { return }
        alias.boundItemId = draft.id
        if alias.boundDomain == nil { alias.boundDomain = draft.autofillHost }
        try? env.repository.updateAlias(alias)
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
            // NEVER derive the title from a secret: the title is plaintext
            // metadata (lists, search, sync) — a password-only item must not
            // put its raw password there. Chain: website domain → username or
            // email → localized "Untitled".
            if let url = draft.fields.first(where: { $0.kind == .url && !$0.isEmpty }),
               let host = FaviconService.host(from: url.value) {
                draft.title = host
            } else if let user = draft.fields.first(where: {
                ($0.kind == .username || $0.kind == .email) && !$0.isEmpty && !$0.protected
            }) {
                draft.title = user.value
            } else {
                draft.title = appString("Untitled")
            }
        }
        do {
            if isNew {
                try env.repository.add(draft)
                bindPendingAlias()
            } else {
                try env.repository.update(draft)
                republishSharedDisplayIfNeeded(for: draft)
            }
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
        }
    }

    /// An active share's recipient sees this item's title via the sealed
    /// display envelope — a rename must reseal it or they keep the old name
    /// forever. Best-effort background work; presentation only, never the grant.
    private func republishSharedDisplayIfNeeded(for item: VaultItem) {
        // Manual-update shares opt out of edit-time propagation — the owner
        // pushes to them explicitly from the share-details sheet.
        let active = env.sharingStore.shares(forItem: item.id)
            .filter { $0.fingerprintConfirmed && $0.isAutoUpdate }
        guard !active.isEmpty else { return }
        let title = item.title.isEmpty ? appString("Shared item") : item.title
        let host = item.urlField?.value.isEmpty == false
            ? URL(string: item.urlField!.value)?.host : nil
        // Editor doesn't know per-share capabilities — publish meta for every
        // shareable field (labels+kinds only, sealed to the recipient).
        let displayFields = Dictionary(uniqueKeysWithValues: item.fields.compactMap { field in
            field.isExtraProtected ? nil
                : (field.id, SharedDisplayEnvelope.FieldMeta(label: field.label,
                                                             kind: field.kind.rawValue))
        })
        // Current plaintexts of shareable fields — republishSharedValues
        // re-seals only the ones each grant actually marks `shared`.
        let currentValues = Dictionary(uniqueKeysWithValues: item.fields.compactMap { field in
            field.isExtraProtected || field.value.isEmpty
                ? nil : (field.id, Data(field.value.utf8))
        })
        Task {
            let nowUnixMs = Int64(Date().timeIntervalSince1970 * 1000)
            for share in active {
                let zoneID = CKRecordZone.ID(zoneName: share.zoneName)
                try? await env.approvalShare.republishDisplayEnvelope(
                    itemId: share.itemId,
                    title: title, websiteHost: host, displayFields: displayFields,
                    zoneID: zoneID, nowUnixMs: nowUnixMs)
                // Edited values follow to the recipient near-realtime (their
                // shared-db push triggers a projection refresh).
                try? await env.approvalShare.republishSharedValues(
                    itemId: share.itemId, values: currentValues,
                    zoneID: zoneID, nowUnixMs: nowUnixMs)
            }
        }
    }
}

// MARK: - Rotation reminder picker

/// Per-item rotation cadence: presets plus a free custom day count. Shown only
/// for password-bearing items (gated at the call site).
///
/// The clock-with-arrow system glyph is a deliberate owner-requested exception
/// to the Polaris-only icon rule — Polaris ships no "time to rotate" mark.
private struct RotationReminderSection: View {
    @Binding var rotateDays: Int

    @State private var showCustom = false
    @State private var customText = ""

    private static let presets: [(label: LocalizedStringResource, value: Int)] = [
        ("Off", 0),
        ("15 days", 15),
        ("30 days", 30),
        ("60 days", 60),
        ("90 days", 90),
        ("180 days", 180),
        ("1 year", 365),
    ]

    private var isPreset: Bool { Self.presets.contains { $0.value == rotateDays } }

    private var currentLabel: String {
        Self.presets.first { $0.value == rotateDays }
            .map { String(localized: $0.label.inAppLocalized) }
            ?? appString("\(rotateDays) days")
    }

    var body: some View {
        Section {
            HStack {
                Label {
                    Text("Rotation reminder")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                Spacer()
                Menu {
                    Picker("", selection: $rotateDays) {
                        ForEach(Self.presets, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                        // A custom cadence stays visible (and checked) instead of
                        // silently snapping back to a preset.
                        if !isPreset {
                            Text("\(rotateDays) days").tag(rotateDays)
                        }
                    }
                    Divider()
                    Button {
                        customText = rotateDays > 0 ? String(rotateDays) : ""
                        showCustom = true
                    } label: {
                        Label("Custom…", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Text(verbatim: currentLabel)
                        .themedForeground(.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        } footer: {
            if rotateDays > 0 {
                Text("Loox reminds you to change this password when the time comes.")
            }
        }
        .listRowBackground(VaultColors.surface)
        .alert("Custom reminder", isPresented: $showCustom) {
            TextField("Days", text: $customText)
                .platformKeyboardType(.numberPad)
            Button("Set") {
                if let days = Int(customText.trimmingCharacters(in: .whitespaces)),
                   (1...3650).contains(days) {
                    rotateDays = days
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How many days between password changes.")
        }
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
            HeaderIconButton(
                Icons.check,
                role: .accent,
                accessibilityLabel: "Save",
                accessibilityIdentifier: "item.editor.save",
                action: save
            )
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
        }
    }
}
