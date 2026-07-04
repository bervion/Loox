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
    @Environment(AppEnvironment.self) private var env
    @State private var selectedPasskey: PasskeyInfo?

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
        Section("Credentials") {
            ForEach(credentialFields) { field in
                EditorFieldRow(field: fieldBinding(field), onScanTOTP: { onScanTOTP(field.id) })
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
        }
        .listRowBackground(VaultColors.surface)
        .sheet(item: $selectedPasskey) { PasskeyDetailSheet(passkey: $0) }
    }

    // MARK: Websites (multi)

    private var websitesSection: some View {
        Section("Websites") {
            ForEach(websiteFields) { field in
                WebsiteFieldRow(field: fieldBinding(field))
            }
            .onDelete { removeFields(at: $0, from: websiteIndices) }
            .onMove { moveFields(from: $0, to: $1, in: websiteIndices) }

            Button {
                draft.fields.append(DynamicField(label: "Website", kind: .url))
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
                EditorFieldRow(field: fieldBinding(field), onScanTOTP: { onScanTOTP(field.id) })
            }
            .onDelete { removeFields(at: $0, from: customIndices) }
            .onMove { moveFields(from: $0, to: $1, in: customIndices) }

            Menu {
                // Websites, Notes and attachments have dedicated homes — offer only the rest.
                ForEach(FieldKind.allCases.filter { ![.url, .multiline, .fileRef].contains($0) }, id: \.self) { kind in
                    Button {
                        draft.fields.append(DynamicField(label: kind.defaultLabel, kind: kind))
                    } label: {
                        Label { Text(kind.title) } icon: { PolarisIcon(kind.iconAsset) }
                    }
                }
            } label: {
                actionRowLabel("Add Field", icon: Icons.addCircle)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            Button { onAddAttachment() } label: {
                actionRowLabel("Add Attachment", icon: "ic_attachment")
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(VaultColors.surface)
    }

    // MARK: Notes (single, fixed bottom)

    @ViewBuilder private var notesSection: some View {
        if let n = noteIndex {
            Section("Notes") {
                TextField("Add a note", text: $draft.fields[n].value, axis: .vertical)
                    .lineLimit(3...10)
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
    private func removeFields(at offsets: IndexSet, from section: [Int]) {
        let targets = offsets.map { section[$0] }.sorted(by: >)
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
        Label { Text(title) } icon: { PolarisIcon(icon) }
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
            PolarisIcon(Icons.personLockFilled, size: 22).themedForeground(.secondary)
        }
        .padding(.vertical, 2)
    }
}
