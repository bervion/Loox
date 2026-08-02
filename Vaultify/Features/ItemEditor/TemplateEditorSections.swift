import SwiftUI
import UniformTypeIdentifiers

/// Registry-driven editor composition for developer-family templates: the
/// template's core sections render first, advanced sections stay collapsed
/// until they hold content or the user opens them, user-added fields collect
/// in a trailing Custom section, and the Git template gets a typed-links
/// section. Screens compose Design System components only — the section
/// structure comes from the registry, never from per-type view code.
struct TemplateEditorSections: View {
    @Binding var draft: VaultItem
    let template: ItemTemplateDefinition
    var onAddAttachment: () -> Void = {}
    var onProtectedDeleteBlocked: () -> Void = {}
    var onRequestExtraProtectionUnlock: () -> Void = {}

    @Environment(AppEnvironment.self) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Advanced sections the user explicitly opened this visit.
    @State private var openedAdvanced: Set<String> = []
    @State private var showKeyImporter = false
    /// Import outcome shown under the import row: honest verification state,
    /// never a stronger claim than the parser proved.
    @State private var importStatus: LocalizedStringKey?

    var body: some View {
        ForEach(template.sections, id: \.id) { section in
            if section.isAdvanced {
                advancedSection(section)
            } else {
                coreSection(section)
            }
        }
        if template.kindID == .gitAccount {
            ItemLinksSection(draft: $draft)
        }
        customSection
    }

    // MARK: Field membership

    /// Draft fields belonging to a template section: stamped section ID first,
    /// then (for legacy-inferred fields that carry only a role) the section
    /// that DECLARES the role.
    private func fieldIDs(in section: TemplateSection) -> [String] {
        draft.fields.compactMap { field in
            if let stamped = field.semantics?.sectionID {
                return stamped == section.id ? field.id : nil
            }
            if let role = field.roleID,
               section.fields.contains(where: { $0.roleID == role }) {
                return field.id
            }
            return nil
        }
    }

    /// Fields outside every template section (user-added custom fields,
    /// attachments, unknown roles).
    private var customFieldIDs: [String] {
        let claimed = Set(template.sections.flatMap { fieldIDs(in: $0) })
        return draft.fields.filter { !claimed.contains($0.id) }.map(\.id)
    }

    /// Section descriptors not yet present on the draft — offerable via the
    /// section's add menu (never silently re-added).
    private func missingDescriptors(in section: TemplateSection) -> [TemplateFieldDescriptor] {
        section.fields.filter { descriptor in
            guard let role = descriptor.roleID else { return false }
            return !draft.fields.contains { $0.roleID == role }
        }
    }

    private func binding(for id: String) -> Binding<DynamicField>? {
        guard let index = draft.fields.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(get: { draft.fields[index] }, set: { draft.fields[index] = $0 })
    }

    // MARK: Sections

    @ViewBuilder private func coreSection(_ section: TemplateSection) -> some View {
        Section {
            // Import-first: an SSH item is usually born from an existing key
            // file, so the import affordance leads its keys section.
            if template.kindID == .sshKey, section.id == "keys" {
                keyImportRow
            }
            sectionRows(section)
        } header: {
            if !section.title.isEmpty { Text(LocalizedStringKey(section.title)) }
        }
        .listRowBackground(VaultColors.surface)
    }

    private var keyImportRow: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Button { showKeyImporter = true } label: {
                Label { Text("Import Key File…") } icon: { VaultIcon(Icons.importData) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let importStatus {
                Text(importStatus)
                    .vaultType(.footnote)
                    .themedForeground(.secondary)
            }
        }
        .fileImporter(isPresented: $showKeyImporter,
                      allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            importKeyFile(at: url)
        }
    }

    /// Reads the picked file (bounded), inspects it locally, and applies the
    /// derived metadata. Original bytes are canonical: the imported text lands
    /// verbatim in its key slot; only derived metadata fields are recomputed.
    private func importKeyFile(at url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              data.count <= SSHKeyInspector.maxInputBytes,
              let text = String(data: data, encoding: .utf8) else {
            importStatus = "Couldn’t read that file as a key"
            Haptics.error()
            return
        }
        Task {
            let result = await SSHKeyInspector.inspectDetached(text)
            draft.fields = SSHKeyImportMapper.fields(applying: result,
                                                     originalText: text,
                                                     to: draft.fields)
            if result.verified {
                importStatus = "Verified"
            } else if result.isEncrypted {
                importStatus = "Passphrase protected"
            } else {
                importStatus = "Saved, not verified"
            }
            Haptics.success()
        }
    }

    @ViewBuilder private func advancedSection(_ section: TemplateSection) -> some View {
        let ids = fieldIDs(in: section)
        if !ids.isEmpty || openedAdvanced.contains(section.id) {
            coreSection(section)
        } else {
            Section {
                Button {
                    withAnimation(.vault(Motion.standard, reduceMotion: reduceMotion)) {
                        _ = openedAdvanced.insert(section.id)
                    }
                } label: {
                    Label {
                        Text(LocalizedStringKey(section.title.isEmpty ? "Details" : section.title))
                    } icon: {
                        VaultIcon(Icons.chevronDown, size: 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Shows additional fields"))
            }
            .listRowBackground(VaultColors.surface)
        }
    }

    @ViewBuilder private func sectionRows(_ section: TemplateSection) -> some View {
        ForEach(fieldIDs(in: section), id: \.self) { id in
            if let binding = binding(for: id) {
                EditorFieldRow(field: binding,
                               category: draft.category,
                               onRequestExtraProtectionUnlock: onRequestExtraProtectionUnlock)
            }
        }
        .onDelete { offsets in removeFields(ids: fieldIDs(in: section), at: offsets) }
        let missing = missingDescriptors(in: section)
        if !missing.isEmpty {
            Menu {
                ForEach(Array(missing.enumerated()), id: \.offset) { _, descriptor in
                    Button {
                        draft.fields.append(descriptor.makeField(sectionID: section.id))
                    } label: {
                        Label { fieldLabelText(descriptor.label) } icon: { VaultIcon(descriptor.kind.iconAsset) }
                    }
                }
            } label: {
                Label { Text("Add Field") } icon: { VaultIcon(Icons.addCircle) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }

    private var customSection: some View {
        Section("Custom Fields") {
            ForEach(customFieldIDs, id: \.self) { id in
                if let binding = binding(for: id) {
                    EditorFieldRow(field: binding,
                                   category: draft.category,
                                   onRequestExtraProtectionUnlock: onRequestExtraProtectionUnlock)
                }
            }
            .onDelete { offsets in removeFields(ids: customFieldIDs, at: offsets) }
            Menu {
                ForEach(FieldKind.allCases.filter { $0 != .fileRef }, id: \.self) { kind in
                    Button {
                        draft.fields.append(DynamicField(label: kind.defaultLabel, kind: kind))
                    } label: {
                        Label { Text(kind.title) } icon: { VaultIcon(kind.iconAsset) }
                    }
                }
            } label: {
                Label { Text("Add Field") } icon: { VaultIcon(Icons.addCircle) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            Button { onAddAttachment() } label: {
                Label { Text("Add Attachment") } icon: { VaultIcon(Icons.attachment) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(VaultColors.surface)
    }

    /// Same extra-protection delete gate the login and flat editors use.
    private func removeFields(ids: [String], at offsets: IndexSet) {
        let doomedIDs = offsets.map { ids[$0] }
        let doomed = draft.fields.filter { doomedIDs.contains($0.id) }
        guard !ExtraProtectionDelete.blocks(doomed, level2Key: env.session.level2Key?.bytes) else {
            onProtectedDeleteBlocked()
            return
        }
        draft.fields.removeAll { doomedIDs.contains($0.id) }
    }
}

// MARK: - Typed links

/// Typed relationships for the Git Hosting Account template: link the PAT,
/// SSH auth key, signing key, or recovery item instead of duplicating the
/// secret. Deleting a linked item elsewhere never cascades — the row renders
/// a broken-link state and offers relink by re-adding.
struct ItemLinksSection: View {
    @Binding var draft: VaultItem

    @Environment(AppEnvironment.self) private var env
    @State private var pickingRole: LinkRoleSelection?

    /// Link roles the Git template offers, with their target template hints.
    private static let offerableRoles: [(role: String, label: String, kinds: [ItemKindID])] = [
        (LinkRole.apiSecret, "Access Token", [.apiSecret, .login, .custom]),
        (LinkRole.authKey, "SSH Key", [.sshKey]),
        (LinkRole.signingKey, "Signing Key", [.sshKey]),
        (LinkRole.recovery, "Recovery Item", [.recoveryCodes, .secureNote, .custom]),
    ]

    private var links: [ItemLink] { draft.semantics?.links ?? [] }

    var body: some View {
        Section("Linked Items") {
            ForEach(links) { link in
                linkRow(link)
            }
            .onDelete { offsets in
                var current = links
                current.remove(atOffsets: offsets)
                setLinks(current)
            }
            Menu {
                ForEach(Self.offerableRoles, id: \.role) { offer in
                    Button {
                        pickingRole = LinkRoleSelection(role: offer.role)
                    } label: {
                        Label { Text(LocalizedStringKey(offer.label)) } icon: { VaultIcon("ic_link") }
                    }
                }
            } label: {
                Label { Text("Link Item") } icon: { VaultIcon(Icons.addCircle) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .listRowBackground(VaultColors.surface)
        .sheet(item: $pickingRole) { selection in
            LinkTargetPickerSheet(
                candidateKinds: Self.offerableRoles.first { $0.role == selection.role }?.kinds ?? [],
                excludedItemIDs: Set(links.map(\.targetItemId) + [draft.id])) { target in
                var current = links
                current.append(ItemLink(roleID: selection.role, targetItemId: target.id))
                setLinks(current)
            }
        }
    }

    private func setLinks(_ links: [ItemLink]) {
        var semantics = draft.semantics ?? ItemSemantics()
        semantics.links = links.isEmpty ? nil : links
        draft.semantics = semantics
    }

    private func roleLabel(_ role: String) -> LocalizedStringKey {
        LocalizedStringKey(Self.offerableRoles.first { $0.role == role }?.label ?? "Linked Item")
    }

    @ViewBuilder private func linkRow(_ link: ItemLink) -> some View {
        let target = env.repository.item(id: link.targetItemId)
        HStack(spacing: Space.s3) {
            VaultIcon(target == nil ? Icons.alert : "ic_link", size: Metric.iconInline)
                .themedForeground(target == nil ? .warning : .iconSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(roleLabel(link.roleID))
                    .vaultType(.caption).fontWeight(.medium)
                    .themedForeground(.accentText)
                Text(target?.title ?? appString("Linked item unavailable"))
                    .vaultType(.body)
                    .themedForeground(target == nil ? .secondary : .primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: Metric.hitMin)
    }
}

/// Identifiable wrapper for the link-role sheet item binding.
private struct LinkRoleSelection: Identifiable {
    let role: String
    var id: String { role }
}

/// Minimal target chooser for a typed link: live vault items whose template
/// matches the link role's candidates, most recent first.
private struct LinkTargetPickerSheet: View {
    let candidateKinds: [ItemKindID]
    let excludedItemIDs: Set<String>
    let onPick: (VaultItem) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private var candidates: [VaultItem] {
        env.repository.items.filter { item in
            guard !excludedItemIDs.contains(item.id) else { return false }
            let kind = item.kindID ?? ItemTemplateRegistry.legacyKind(for: item.category)
            return candidateKinds.contains(kind)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    Text("No matching items in your vault yet")
                        .vaultType(.subhead)
                        .themedForeground(.secondary)
                }
                ForEach(candidates) { item in
                    Button {
                        onPick(item)
                        dismiss()
                    } label: {
                        HStack(spacing: Space.s3) {
                            VaultIcon(ItemTemplateRegistry
                                .definition(for: item.kindID ?? ItemTemplateRegistry.legacyKind(for: item.category))?
                                .iconAsset ?? item.category.iconAsset,
                                size: Metric.iconInline)
                                .themedForeground(.iconSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title.isEmpty ? appString("Untitled") : item.title)
                                    .vaultType(.body)
                                    .themedForeground(.primary)
                                    .lineLimit(1)
                                if let subtitle = item.subtitle {
                                    Text(subtitle)
                                        .vaultType(.footnote)
                                        .themedForeground(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(minHeight: Metric.hitMin)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(VaultColors.surface)
                }
            }
            .navigationTitle(Text("Link Item"))
            .platformNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .platformTopBarLeading) {
                    Button { dismiss() } label: {
                        VaultIcon(Icons.close, size: Metric.iconInline)
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .platformPresentationDetents([.medium, .large])
    }
}
