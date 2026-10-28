import SwiftUI

/// The Login editor body, grouped into fixed sections (Credentials · Websites · Custom
/// Fields · Notes) instead of one flat field list. Operates on the shared `draft.fields`
/// via index-based bindings; each section renders the fields whose `kind` belongs to it,
/// so changing a field's kind moves it between sections. Only used for `.login` items —
/// other categories keep the flat editor.
struct LoginEditorSections: View {
    @Binding var draft: VaultItem
    /// Present the TOTP scanner for the given field id.
    var onScanTOTP: (String) -> Void
    /// Present the attachment picker.
    var onAddAttachment: () -> Void
    /// A swipe tried to delete a field this session cannot open. The editor owns
    /// the explanation (one alert for both editors) rather than each section
    /// growing its own.
    var onProtectedDeleteBlocked: () -> Void = {}
    /// Lets a locked Extra-Protection row re-raise the editor's unlock prompt.
    var onRequestExtraProtectionUnlock: () -> Void = {}
    var onAliasDetached: () -> Void = {}
    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    /// The status dot grows with its caption label, so it stays readable at
    /// accessibility text sizes instead of shrinking to a speck beside them.
    @ScaledMetric(relativeTo: .caption) private var statusDotSize: CGFloat = 8
    @State private var selectedPasskey: PasskeyInfo?
    /// The website row just created via "Add Website" — it claims keyboard focus
    /// on appear so typing continues there, not in the previously focused field.
    @State private var addedWebsiteFieldId: String?
    @State private var aliasToDetach: DynamicField?

    /// Field kinds shown in the Credentials section, in template order.
    private let credentialKinds: Set<FieldKind> = [.username, .email, .password, .totp]

    var body: some View {
        credentialsSection
        websitesSection
        customSection
        notesSection
    }

    // MARK: Credentials

    private var credentialsSection: some View {
        Section {
            ForEach(credentialFields) { field in
                if let match = privateEmailMatch(for: field) {
                    attachedPrivateEmailRow(field: fieldBinding(field), match: match)
                } else {
                    EditorFieldRow(field: fieldBinding(field), onScanTOTP: { onScanTOTP(field.id) },
                                   onRequestExtraProtectionUnlock: onRequestExtraProtectionUnlock)
                }
            }
            .onMove { moveFields(from: $0, to: $1, in: credentialIndices) }
            // Passkeys can't be created here (the OS mints them via WebAuthn). Tapping a row
            // opens the passkey detail (view + delete-with-confirmation) — same as the item
            // detail screen. NOT wired to edit-mode `.onDelete`: deferring the real delete to a
            // confirmation left the swiped row half-removed then snapping back (layout flicker).
            ForEach(linkedPasskeys) { passkey in
                Button { selectedPasskey = passkey } label: { passkeyRow(passkey) }
                    .buttonStyle(.plain)
            }
        } header: {
            Text("Credentials")
        } footer: {
            // What the × leaves behind, in the quiet footnote voice under the
            // card. Pause/delete live in Private Email, which this names; the
            // editor only ever attaches or detaches the field.
            if attachedPrivateEmail != nil {
                Text("Unlinking keeps this address receiving mail. Manage forwarding in Private Email.")
            }
        }
        .listRowBackground(VaultColors.surface)
        // The system alert, like the editor's discard confirmation: an action
        // sheet here is a small popover anchored to the × on iOS 26.
        .alert("Unlink this service?", isPresented: Binding(
            get: { aliasToDetach != nil }, set: { if !$0 { aliasToDetach = nil } })) {
            Button("Cancel", role: .cancel) { aliasToDetach = nil }
            Button("Unlink", role: .destructive) {
                if let field = aliasToDetach,
                   !ExtraProtectionDelete.blocks([field], level2Key: env.session.level2Key?.bytes) {
                    draft.fields.removeAll { $0.id == field.id }
                    onAliasDetached()
                }
                aliasToDetach = nil
            }
        } message: {
            Text("This removes the private email from this vault item. Forwarding and the service account stay unchanged.")
        }
        .sheet(item: $selectedPasskey) { PasskeyDetailSheet(passkey: $0) }
    }

    // MARK: Private email recognition (attached alias)

    /// Whether `field` (email/username) currently holds one of the active
    /// persona's aliases (INV-R03) — regardless of the alias's live status, so
    /// a paused alias still shows the private-email row instead of silently
    /// reverting to a plain-email look.
    private func privateEmailMatch(for field: DynamicField) -> PrivateEmailMatch? {
        guard field.kind == .email, field.label == AliasWriteback.privateEmailLabel,
              let canonical = try? AliasWriteback.readableField(on: draft), canonical.id == field.id else { return nil }
        return PrivateEmailMatch.resolve(kind: field.kind, value: field.value, repository: env.repository)
    }

    /// The single Credentials field (there's at most one email/username field
    /// per login template) currently attached to an alias, if any.
    private var attachedPrivateEmail: (field: DynamicField, match: PrivateEmailMatch)? {
        for field in credentialFields {
            if let match = privateEmailMatch(for: field) { return (field, match) }
        }
        return nil
    }

    /// The attached-alias row: label + status dot, the address with a small
    /// detach (×) button, and where its mail goes underneath. Same rhythm as
    /// `EditorFieldRow` (caption label, value, 6pt apart) so it reads as one
    /// more field in the card rather than a feature panel.
    private func attachedPrivateEmailRow(field: Binding<DynamicField>, match: PrivateEmailMatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // The dot carries the alias state (green while it forwards). It is
            // said in words for VoiceOver, and shown in words too when the user
            // asked iOS not to rely on colour alone.
            HStack(spacing: Space.s2) {
                Text("Private email")
                    .vaultType(.caption)
                    .themedForeground(.secondary)
                StatusDot(role: match.statusRole, size: statusDotSize)
                if differentiateWithoutColor {
                    Text(verbatim: match.statusLabel)
                        .vaultType(.caption)
                        .themedForeground(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Private email"))
            .accessibilityValue(Text(verbatim: match.statusLabel))

            HStack(spacing: Space.s2) {
                Text(verbatim: field.wrappedValue.value)
                    .vaultType(.subhead)
                    .themedForeground()
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: Space.s2)
                Button {
                    // Detach only: the alias itself is untouched (INV kept alive) —
                    // pause/delete lives in Private Email management, not here.
                    aliasToDetach = field.wrappedValue
                } label: {
                    VaultIcon(Icons.close, size: 12)
                        .themedForeground(.secondary)
                        .frame(minWidth: Metric.hitMin, minHeight: Metric.hitMin)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Detach private email"))
            }

            if let destination = match.destination {
                forwardsToLine(destination)
            }
        }
        .padding(.vertical, 2)
    }

    /// "Forwards to {destination}" as one caption that wraps instead of
    /// truncating: the destination is the part worth reading, so it keeps its
    /// tail on an SE and at accessibility text sizes. The label stays secondary
    /// and the address takes the primary text colour.
    private func forwardsToLine(_ destination: String) -> some View {
        let theme = env.theme.active
        var label = AttributedString(appString("Forwards to") + " ")
        label.foregroundColor = theme.color(.secondary)
        var address = AttributedString(destination)
        address.foregroundColor = theme.color(.primary)
        return Text(label + address)
            .vaultType(.caption)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Websites (multi)

    private var websitesSection: some View {
        Section("Websites") {
            ForEach(websiteFields) { field in
                // A sealed website goes through the shared row so it follows the
                // same lock state as every other protected field. `WebsiteFieldRow`
                // would put the raw `v2g:` payload in an editable text field.
                if field.isExtraProtected {
                    EditorFieldRow(field: fieldBinding(field),
                                   onRequestExtraProtectionUnlock: onRequestExtraProtectionUnlock)
                } else {
                    WebsiteFieldRow(field: fieldBinding(field),
                                    autoFocus: field.id == addedWebsiteFieldId)
                }
            }
            .onDelete { removeFields(at: $0, from: websiteIndices) }
            .onMove { moveFields(from: $0, to: $1, in: websiteIndices) }

            Button {
                let field = DynamicField(label: "Website", kind: .url)
                addedWebsiteFieldId = field.id
                draft.fields.append(field)
            } label: {
                actionRowLabel("Add Website", icon: Icons.addCircle)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(VaultColors.surface)
    }

    // MARK: Custom fields

    private var customSection: some View {
        Section("Custom Fields") {
            ForEach(customFields) { field in
                EditorFieldRow(field: fieldBinding(field), onScanTOTP: { onScanTOTP(field.id) },
                                   onRequestExtraProtectionUnlock: onRequestExtraProtectionUnlock)
            }
            .onDelete { removeFields(at: $0, from: customIndices) }
            .onMove { moveFields(from: $0, to: $1, in: customIndices) }

            Menu {
                // Websites, Notes and attachments have dedicated homes — offer only the rest.
                ForEach(FieldKind.allCases.filter { ![.url, .multiline, .fileRef].contains($0) }, id: \.self) { kind in
                    Button {
                        draft.fields.append(DynamicField(label: kind.defaultLabel, kind: kind))
                    } label: {
                        Label { Text(kind.title) } icon: { VaultIcon(kind.iconAsset) }
                    }
                }
            } label: {
                actionRowLabel("Add Field", icon: Icons.addCircle)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            Button { onAddAttachment() } label: {
                actionRowLabel("Add Attachment", icon: Icons.attachment)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(VaultColors.surface)
    }

    // MARK: Notes (single, fixed bottom)

    @ViewBuilder private var notesSection: some View {
        if let n = noteIndex {
            Section("Notes") {
                // Same reason as the website rows: a sealed note must not land in
                // a plain text field as its own ciphertext.
                if draft.fields[n].isExtraProtected {
                    EditorFieldRow(field: $draft.fields[n],
                                   onRequestExtraProtectionUnlock: onRequestExtraProtectionUnlock)
                } else {
                    TextField("Add a note", text: $draft.fields[n].value, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    // MARK: Section membership (by field kind)

    private var credentialIndices: [Int] {
        draft.fields.indices.filter { credentialKinds.contains(draft.fields[$0].kind) }
    }

    private var websiteIndices: [Int] {
        draft.fields.indices.filter { draft.fields[$0].kind == .url }
    }

    /// The single note field is the first `.multiline`; everything else that isn't a
    /// credential or a website falls into Custom (including any extra multiline notes).
    private var noteIndex: Int? {
        draft.fields.firstIndex { $0.kind == .multiline }
    }

    private var customIndices: [Int] {
        let note = noteIndex
        return draft.fields.indices.filter { i in
            let kind = draft.fields[i].kind
            return !credentialKinds.contains(kind) && kind != .url && i != note
        }
    }

    // Section field lists (parallel to the *Indices), iterated by stable field id so
    // reordering animates smoothly (a positional `id: \.self` made the drop lag/settle late).
    private var credentialFields: [DynamicField] { credentialIndices.map { draft.fields[$0] } }
    private var websiteFields: [DynamicField] { websiteIndices.map { draft.fields[$0] } }
    private var customFields: [DynamicField] { customIndices.map { draft.fields[$0] } }

    /// Binding into `draft.fields` for a given field (looked up by stable id).
    private func fieldBinding(_ field: DynamicField) -> Binding<DynamicField> {
        let index = draft.fields.firstIndex(where: { $0.id == field.id }) ?? 0
        return $draft.fields[index]
    }

    /// Passkeys attached to this login by relying-party ↔ website host match.
    private var linkedPasskeys: [PasskeyInfo] {
        guard draft.autofillHost != nil else { return [] }
        return env.repository.passkeys
            .filter { draft.matchesRelyingParty($0.relyingParty) }
            .sorted { ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt) }
    }

    // MARK: Helpers

    /// Delete rows at `offsets` (positions within a filtered section's index list) from
    /// `draft.fields`, removing high indices first so earlier removals don't shift them.
    ///
    /// The SINGLE gate for every swipe-delete in the Login editor: a field this
    /// session cannot open must not be swiped away. Keeping the check here (rather
    /// than at each `.onDelete`) is what stops a fourth call site from forgetting it.
    private func removeFields(at offsets: IndexSet, from section: [Int]) {
        let targets = offsets.map { section[$0] }.sorted(by: >)
        guard !ExtraProtectionDelete.blocks(targets.map { draft.fields[$0] },
                                            level2Key: env.session.level2Key?.bytes) else {
            Haptics.warning()
            onProtectedDeleteBlocked()
            return
        }
        for index in targets { draft.fields.remove(at: index) }
    }

    /// Reorder rows WITHIN a section. `offsets`/`destination` index into the section's
    /// own row list; only the fields occupying this section's slots in `draft.fields` are
    /// permuted, leaving other sections' fields untouched.
    private func moveFields(from offsets: IndexSet, to destination: Int, in section: [Int]) {
        var reordered = section.map { draft.fields[$0] }
        reordered.move(fromOffsets: offsets, toOffset: destination)
        for (slot, field) in zip(section, reordered) { draft.fields[slot] = field }
    }

    /// Full-width label for an add-row action so the WHOLE row is tappable — a bare
    /// `Label` only registers taps on its text/icon, leaving the rest of the row dead.
    private func actionRowLabel(_ title: LocalizedStringKey, icon: String) -> some View {
        Label { Text(title) } icon: { VaultIcon(icon) }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func passkeyRow(_ passkey: PasskeyInfo) -> some View {
        HStack(spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: passkey.userName).vaultType(.body).themedForeground().lineLimit(1)
                Text("Created \(passkey.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .vaultType(.caption).themedForeground(.secondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VaultIcon(Icons.personLockFilled, size: 22).themedForeground(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Swipe-delete gate for Extra Protection

/// Whether a swipe-delete may proceed. Shared by both editors (Login sections and
/// the flat field list) so the rule lives in one place.
///
/// A sealed field is destroyed by a swipe, and the value inside it is exactly the
/// thing the person swiping cannot read. So it stays put while this session cannot
/// open it: sealed under the app-wide Extra Password with Level-2 locked, or sealed
/// under a per-field custom code (which the editor never holds — that one is
/// unsealed from the item view, where its code is asked for).
/// The test is a real open, not "the session holds some Level-2 key": after a
/// restore that adopted a foreign wrap, a field sealed under the previous L2SK
/// stays unreadable even though `level2Key` is set, and the row renders locked.
/// Trusting the boolean there would let a swipe destroy exactly the value the
/// person swiping cannot read.
nonisolated enum ExtraProtectionDelete {
    static func blocks(_ fields: [DynamicField], level2Key: [UInt8]?) -> Bool {
        fields.contains { field in
            guard field.isExtraProtected else { return false }
            guard SecretGuard.scheme(of: field.value) == .level2, let level2Key else { return true }
            return (try? SecretGuard.openLevel2(field.value, l2Key: level2Key)) == nil
        }
    }
}
